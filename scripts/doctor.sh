#!/usr/bin/env bash
# P0-J1 取证环境自检（只读）；P0-J2 安全加固。
#
# 用法：bash scripts/doctor.sh [--json]
# 输出：每项一行「状态 <TAB> 检查名 <TAB> 说明」，最后一行汇总
#       `summary: N ok, N warn, N fail, N skip`；加 --json 时改为输出 JSON。
# 退出码：有任何 FAIL 时为 1，否则为 0。
#
# 安全：不打印、不记录任何密钥（只写“已设置/未设置”）；密钥不进命令行参数
#       （经标准输入交给 curl）；端点必须显式以 http:// 或 https:// 开头；
#       密钥含换行/回车时直接拒绝；只发 GET /models；不写任何文件、
#       不修改环境、不安装任何东西。
# 兼容：macOS 自带 bash 3.2 与 Linux bash（不用关联数组、mapfile、${var,,}）。
#       注意：bash 3.2 会把 $VAR 后紧跟的非 ASCII 字节并入变量名，
#       所有变量展开一律写成 ${VAR} 形式。

set -u

JSON_MODE=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=1 ;;
    *) ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

HAS_PYTHON3=1
if ! command -v python3 >/dev/null 2>&1; then
  HAS_PYTHON3=0
fi

# 内部字段分隔符（ASCII US，0x1f），只在内存里使用
US=$(printf '\037')

CHECKS_BLOB=""
N_OK=0
N_WARN=0
N_FAIL=0
N_SKIP=0

add_check() {
  # 参数：状态 检查名 说明
  if [ -z "$CHECKS_BLOB" ]; then
    CHECKS_BLOB="$1$US$2$US$3"
  else
    CHECKS_BLOB="$CHECKS_BLOB
$1$US$2$US$3"
  fi
  case "$1" in
    OK) N_OK=$((N_OK + 1)) ;;
    WARN) N_WARN=$((N_WARN + 1)) ;;
    FAIL) N_FAIL=$((N_FAIL + 1)) ;;
    SKIP) N_SKIP=$((N_SKIP + 1)) ;;
  esac
}

env_value() {
  printenv "$1" 2>/dev/null || true
}

# ----------------------------------------------------------------- flutter
EXPECTED_FLUTTER=$(sed -n 's/^[[:space:]]*flutter-version:[[:space:]]*//p' \
  "$REPO_ROOT/.github/workflows/verify.yml" 2>/dev/null \
  | head -n 1 | tr -d '[:space:]' | tr -d '"' | tr -d "'")
FLUTTER_BIN=$(command -v flutter 2>/dev/null || true)
if [ -z "$FLUTTER_BIN" ]; then
  add_check FAIL flutter "找不到 flutter 命令"
else
  LOCAL_FLUTTER=$(flutter --version 2>/dev/null | head -n 1 | awk '{print $2}')
  if [ -z "$LOCAL_FLUTTER" ]; then
    add_check FAIL flutter "flutter --version 没有输出"
  elif [ -z "$EXPECTED_FLUTTER" ]; then
    add_check WARN flutter "本机 Flutter ${LOCAL_FLUTTER}；无法从 verify.yml 读取 flutter-version"
  elif [ "$LOCAL_FLUTTER" = "$EXPECTED_FLUTTER" ]; then
    add_check OK flutter "Flutter ${LOCAL_FLUTTER} 与 verify.yml 一致"
  else
    add_check WARN flutter "本机 Flutter ${LOCAL_FLUTTER}，verify.yml 要求 ${EXPECTED_FLUTTER}"
  fi
fi

# ----------------------------------------------------------------- devices
if [ -z "$FLUTTER_BIN" ]; then
  add_check WARN devices "flutter 不可用，无法枚举设备"
elif [ "$HAS_PYTHON3" -eq 0 ]; then
  add_check WARN devices "缺少 python3，无法解析设备列表"
else
  DEVICES_JSON=$(flutter devices --machine 2>/dev/null)
  DEVICES_RC=$?
  if [ "$DEVICES_RC" -ne 0 ] || [ -z "$DEVICES_JSON" ]; then
    add_check WARN devices "flutter devices --machine 失败"
  else
    DEVICES_SUMMARY=$(printf '%s' "$DEVICES_JSON" | python3 -c '
import json
import sys

text = sys.stdin.read()
start = text.find("[")
try:
    data = json.loads(text[start:]) if start != -1 else []
except Exception:
    print("__UNPARSEABLE__")
    sys.exit(0)

items = []
for dev in data:
    if not isinstance(dev, dict):
        continue
    name = dev.get("name", "?")
    platform = dev.get("targetPlatform", "?")
    items.append("%s(%s)" % (name, platform))

if not items:
    print("__NONE__")
else:
    print(", ".join(items))
' 2>/dev/null)
    case "$DEVICES_SUMMARY" in
      "") add_check WARN devices "设备列表解析失败" ;;
      "__UNPARSEABLE__") add_check WARN devices "设备列表无法解析" ;;
      "__NONE__") add_check WARN devices "没有任何设备" ;;
      *) add_check OK devices "$DEVICES_SUMMARY" ;;
    esac
  fi
fi

# ----------------------------------------------------------------- android
HAS_ADB=0
HAS_JAVA=0
if command -v adb >/dev/null 2>&1 && adb version >/dev/null 2>&1; then
  HAS_ADB=1
fi
if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
  HAS_JAVA=1
fi
if [ "$HAS_ADB" -eq 1 ] && [ "$HAS_JAVA" -eq 1 ]; then
  add_check OK android "adb 与 java 均可用"
elif [ "$HAS_ADB" -eq 0 ] && [ "$HAS_JAVA" -eq 0 ]; then
  add_check WARN android "缺少 adb 和 java"
elif [ "$HAS_ADB" -eq 0 ]; then
  add_check WARN android "缺少 adb"
else
  add_check WARN android "缺少 java"
fi

# ----------------------------------------------------------------- xcode
UNAME_S=$(uname 2>/dev/null || echo unknown)
if [ "$UNAME_S" != "Darwin" ]; then
  add_check SKIP xcode "非 macOS，跳过"
else
  XCODE_VER=$(xcodebuild -version 2>/dev/null | head -n 1)
  if [ -z "$XCODE_VER" ]; then
    add_check WARN xcode "xcodebuild 不可用或失败"
  else
    add_check OK xcode "$XCODE_VER"
  fi
fi

# ----------------------------------------------------------------- proxy
PROXY_HIT=""
for name in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do
  value=$(env_value "$name")
  if [ -n "$value" ]; then
    PROXY_HIT="${PROXY_HIT} $name"
  fi
done
if [ -n "$PROXY_HIT" ]; then
  add_check WARN proxy "检测到代理变量:${PROXY_HIT}；运行 flutter test 前请按 scripts/verify.sh 去掉代理"
else
  add_check OK proxy "未检测到代理变量"
fi

# ----------------------------------------------------------------- model-env
MODEL_ENDPOINT=$(env_value MUYON_EVAL_MODEL_ENDPOINT)
MODEL_ID=$(env_value MUYON_EVAL_MODEL_ID)
# P0-J3：直接展开而不是经 $(printenv)，否则末尾换行会被命令替换吞掉，
# 带末尾 LF 的密钥会被误判为合法。
MODEL_KEY=${MUYON_EVAL_MODEL_KEY-}
MODEL_ENV_STATUS=SKIP
MODEL_IS_REMOTE=0
IS_LOOPBACK=0

if [ -z "$MODEL_ENDPOINT" ] && [ -z "$MODEL_ID" ]; then
  add_check SKIP model-env "未配置真实模型，只能跑夹具"
  MODEL_ENV_STATUS=SKIP
elif [ -z "$MODEL_ENDPOINT" ] || [ -z "$MODEL_ID" ]; then
  add_check FAIL model-env "MUYON_EVAL_MODEL_ENDPOINT 与 MUYON_EVAL_MODEL_ID 必须同时设置"
  MODEL_ENV_STATUS=FAIL
else
  # P0-J2：端点必须显式以 http:// 或 https:// 开头，否则 :// 出现在
  # 字符串其它位置时可能把远程端点伪装成本机（解析 authority 之前先判）。
  case "$MODEL_ENDPOINT" in
    http://*|https://*) EP_SCHEME_OK=1 ;;
    *) EP_SCHEME_OK=0 ;;
  esac
  if [ "$EP_SCHEME_OK" -eq 0 ]; then
    add_check FAIL model-env "端点必须以 http:// 或 https:// 开头"
    MODEL_ENV_STATUS=FAIL
  else
    # F1：取 authority（scheme:// 之后、第一个 / ? # 之前），用户信息一律
    # 拒绝；主机名做精确匹配，只认 localhost、127.0.0.1、[::1]。
    EP_AUTH="$MODEL_ENDPOINT"
    case "$EP_AUTH" in
      *://*) EP_AUTH=${EP_AUTH#*://} ;;
    esac
    EP_AUTH=${EP_AUTH%%[/?#]*}

    if [ "${EP_AUTH#*@}" != "$EP_AUTH" ]; then
      add_check FAIL model-env "端点不应包含用户信息"
      MODEL_ENV_STATUS=FAIL
    else
      EP_HOST="$EP_AUTH"
      case "$EP_HOST" in
        \[*)
          EP_INNER=${EP_HOST#*[}
          EP_INNER=${EP_INNER%%]*}
          EP_HOST="[${EP_INNER}]"
          ;;
        *)
          EP_HOST=${EP_HOST%:*}
          ;;
      esac
      case "$EP_HOST" in
        localhost|127.0.0.1|\[::1\]) IS_LOOPBACK=1 ;;
      esac
      IS_HTTPS=0
      case "$MODEL_ENDPOINT" in
        https://*) IS_HTTPS=1 ;;
      esac
      if [ "$IS_LOOPBACK" -eq 1 ]; then
        add_check OK model-env "本机端点已配置"
        MODEL_ENV_STATUS=OK
      elif [ "$IS_HTTPS" -eq 1 ]; then
        add_check OK model-env "远程端点（HTTPS）已配置"
        MODEL_ENV_STATUS=OK
        MODEL_IS_REMOTE=1
      else
        add_check FAIL model-env "远程端点必须使用 HTTPS"
        MODEL_ENV_STATUS=FAIL
      fi
    fi
  fi
fi

# ----------------------------------------------------------------- model-key
MODEL_KEY_STATUS=SKIP
if [ "$MODEL_ENV_STATUS" = "SKIP" ]; then
  add_check SKIP model-key "未配置真实模型"
  MODEL_KEY_STATUS=SKIP
elif [ "$MODEL_ENV_STATUS" = "FAIL" ]; then
  add_check SKIP model-key "模型配置无效，无法判断"
  MODEL_KEY_STATUS=SKIP
else
  # P0-J2：密钥含换行或回车时，注入 curl 配置行的风险不可接受，直接拒绝。
  KEY_BAD=0
  case "$MODEL_KEY" in
    *$'\n'*|*$'\r'*) KEY_BAD=1 ;;
  esac
  if [ "$KEY_BAD" -eq 1 ]; then
    add_check FAIL model-key "密钥含换行或回车字符"
    MODEL_KEY_STATUS=FAIL
  elif [ "$MODEL_IS_REMOTE" -eq 1 ]; then
    if [ -n "$MODEL_KEY" ]; then
      add_check OK model-key "远程端点，密钥已设置"
      MODEL_KEY_STATUS=OK
    else
      add_check FAIL model-key "远程端点需要设置 MUYON_EVAL_MODEL_KEY"
      MODEL_KEY_STATUS=FAIL
    fi
  else
    add_check OK model-key "本机端点不需要密钥"
    MODEL_KEY_STATUS=OK
  fi
fi

# ----------------------------------------------------------------- model-reach
if [ "$MODEL_ENV_STATUS" = "OK" ] && [ "$MODEL_KEY_STATUS" = "OK" ]; then
  # F5/P0-J2：先去尾部斜杠，再剥离 /chat/completions，避免得到 //models
  MODELS_URL=$(printf '%s' "$MODEL_ENDPOINT" | sed -e 's#/*$##' -e 's#/chat/completions$##')
  MODELS_URL="$MODELS_URL/models"

  # F4/P0-J2：回环端点绕过代理；其余保持系统代理设置。可选参数放数组里，
  # 空数组在 set -u 下用 ${arr[@]+...} 展开（bash 3.2 兼容）。
  CURL_EXTRA=()
  if [ "$IS_LOOPBACK" -eq 1 ]; then
    CURL_EXTRA=(--noproxy '*')
  fi

  # F2/P0-J2：密钥经标准输入（curl -K -）传递，不进命令行参数；URL 经
  # --url 传入（防以 - 开头的端点被当成选项），协议限定 http/https。
  if [ -n "$MODEL_KEY" ]; then
    ESC_KEY=$(printf '%s' "$MODEL_KEY" | sed 's/\\/\\\\/g; s/"/\\"/g')
    HTTP_CODE=$(printf 'header = "Authorization: Bearer %s"\n' "$ESC_KEY" \
      | curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --proto '=http,https' \
        ${CURL_EXTRA[@]+"${CURL_EXTRA[@]}"} -K - --url "$MODELS_URL" 2>/dev/null)
  else
    HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --proto '=http,https' \
      ${CURL_EXTRA[@]+"${CURL_EXTRA[@]}"} --url "$MODELS_URL" 2>/dev/null)
  fi
  case "$HTTP_CODE" in
    200) add_check OK model-reach "GET models 返回 200" ;;
    401|403) add_check FAIL model-reach "凭据被拒绝（HTTP ${HTTP_CODE}）" ;;
    ""|000) add_check WARN model-reach "无法连接（HTTP 000）" ;;
    *) add_check WARN model-reach "无法确认（HTTP ${HTTP_CODE}）" ;;
  esac
else
  add_check SKIP model-reach "前置检查未通过"
fi

# ----------------------------------------------------------------- 输出
if [ "$JSON_MODE" -eq 1 ]; then
  if [ "$HAS_PYTHON3" -eq 0 ]; then
    printf 'doctor: --json 需要 python3，但未找到 python3\n' >&2
    exit 1
  fi
  printf '%s\n' "$CHECKS_BLOB" | python3 -c '
import json
import sys

us = chr(31)
checks = []
counts = {"ok": 0, "warn": 0, "fail": 0, "skip": 0}

for raw in sys.stdin:
    raw = raw.rstrip("\n")
    if not raw:
        continue
    parts = raw.split(us)
    status = parts[0] if len(parts) > 0 else ""
    name = parts[1] if len(parts) > 1 else ""
    detail = parts[2] if len(parts) > 2 else ""
    checks.append({"status": status, "name": name, "detail": detail})
    key = status.lower()
    if key in counts:
        counts[key] += 1

print(json.dumps({"checks": checks, "summary": counts}, ensure_ascii=False))
'
else
  printf '%s\n' "$CHECKS_BLOB" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    st=${line%%"$US"*}
    rest=${line#*"$US"}
    name=${rest%%"$US"*}
    detail=${rest#*"$US"}
    printf '%s\t%s\t%s\n' "$st" "$name" "$detail"
  done
  printf 'summary: %d ok, %d warn, %d fail, %d skip\n' "$N_OK" "$N_WARN" "$N_FAIL" "$N_SKIP"
fi

if [ "$N_FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
