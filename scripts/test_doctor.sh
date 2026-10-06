#!/usr/bin/env bash
# P0-J1 `scripts/doctor.sh` 的场景测试；P0-J2 增加安全加固场景。
# 用临时目录里的假 flutter / adb / java / curl 模拟环境；
# 不依赖网络、不依赖真实 Flutter。全部场景通过 → 退出 0，否则退出 1。

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DOCTOR="$SCRIPT_DIR/doctor.sh"

PASSED=0
FAILED=0

pass() {
  PASSED=$((PASSED + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL %s\n' "$1"
}

if [ ! -f "$DOCTOR" ]; then
  printf '找不到 %s\n' "$DOCTOR"
  exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/doctor-test.XXXXXX") || exit 1
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

# 与 verify.yml 一致的期望版本（不写死）
EXPECTED_FLUTTER=$(sed -n 's/^[[:space:]]*flutter-version:[[:space:]]*//p' \
  "$SCRIPT_DIR/../.github/workflows/verify.yml" 2>/dev/null \
  | head -n 1 | tr -d '[:space:]' | tr -d '"' | tr -d "'")
if [ -z "$EXPECTED_FLUTTER" ]; then
  printf '无法从 .github/workflows/verify.yml 读取 flutter-version\n'
  exit 1
fi

# ------------------------------------------------------------------ 假命令
cat > "$FAKE_BIN/flutter" <<'FAKE_FLUTTER'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'Flutter %s • channel stable\n' "${FAKE_FLUTTER_VERSION:-0.0.0}"
  exit 0
fi
if [ "${1:-}" = "devices" ] && [ "${2:-}" = "--machine" ]; then
  printf '%s\n' '[{"name":"Fake Phone","targetPlatform":"android-arm64"},{"name":"Fake Workstation","targetPlatform":"darwin"}]'
  exit 0
fi
exit 1
FAKE_FLUTTER

cat > "$FAKE_BIN/adb" <<'FAKE_ADB'
#!/usr/bin/env bash
printf 'Android Debug Bridge version 1.0.41\n'
exit 0
FAKE_ADB

cat > "$FAKE_BIN/java" <<'FAKE_JAVA'
#!/usr/bin/env bash
printf 'openjdk version "17.0.0"\n' >&2
exit 0
FAKE_JAVA

cat > "$FAKE_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
has_k=0
for a in "$@"; do
  if [ "$a" = "-K" ]; then
    has_k=1
  fi
done
if [ -n "${FAKE_CURL_ARGS_FILE:-}" ]; then
  printf '%s\n' "$@" > "$FAKE_CURL_ARGS_FILE"
  if [ "$has_k" -eq 1 ]; then
    cat > "${FAKE_CURL_ARGS_FILE}.stdin"
  fi
fi
printf '%s\n' "${FAKE_CURL_CODE:-200}"
exit 0
FAKE_CURL

chmod +x "$FAKE_BIN/flutter" "$FAKE_BIN/adb" "$FAKE_BIN/java" "$FAKE_BIN/curl"

# ------------------------------------------------------------------ 辅助
# 运行 doctor：第一个参数是 "" 或 --json，其余参数为额外的 NAME=VALUE 环境变量
run_doctor() {
  doctor_mode="$1"
  shift
  OUT=$(env -i PATH="$FAKE_BIN:$PATH" HOME="$HOME" \
    "$@" bash "$DOCTOR" $doctor_mode < /dev/null 2>&1)
  RC=$?
}

line_is() {
  # 检查输出里是否有以「状态 TAB 名称」开头的行
  printf '%s\n' "$OUT" | grep -qF "$1"
}

# ------------------------------------------------------------------ 场景 1
# 版本一致时 flutter 为 OK
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER"
if line_is "$(printf 'OK\tflutter')" && [ "$RC" -eq 0 ]; then
  pass "版本一致时 flutter 为 OK"
else
  fail "版本一致时 flutter 为 OK"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 2
# 版本不同时为 WARN
run_doctor "" FAKE_FLUTTER_VERSION="0.0.1"
if line_is "$(printf 'WARN\tflutter')" && [ "$RC" -eq 0 ]; then
  pass "版本不同时为 WARN"
else
  fail "版本不同时为 WARN"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 3
# 没配置模型时 model-env 为 SKIP 且退出码 0
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER"
if line_is "$(printf 'SKIP\tmodel-env')" && [ "$RC" -eq 0 ]; then
  pass "没配置模型时 model-env 为 SKIP 且退出码 0"
else
  fail "没配置模型时 model-env 为 SKIP 且退出码 0"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 4
# 远程 http:// 端点时 model-env 为 FAIL 且退出码 1
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  MUYON_EVAL_MODEL_ENDPOINT="http://api.example.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model"
if line_is "$(printf 'FAIL\tmodel-env')" && [ "$RC" -eq 1 ]; then
  pass "远程 http:// 端点时 model-env 为 FAIL 且退出码 1"
else
  fail "远程 http:// 端点时 model-env 为 FAIL 且退出码 1"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 5
# 假 curl 返回 401 时 model-reach 为 FAIL
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" FAKE_CURL_CODE=401 \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY="dummy-key-for-test"
if line_is "$(printf 'FAIL\tmodel-reach')" && [ "$RC" -eq 1 ]; then
  pass "假 curl 返回 401 时 model-reach 为 FAIL"
else
  fail "假 curl 返回 401 时 model-reach 为 FAIL"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 6
# 密钥不出现在任何输出里；--json 可解析且包含 model-key 检查项
SECRET="sk-test-secret"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY="$SECRET"
OUT_HUMAN="$OUT"
run_doctor --json FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY="$SECRET"
OUT_JSON="$OUT"
SCENARIO6_OK=1
if printf '%s' "$OUT_HUMAN" | grep -qF "$SECRET"; then
  SCENARIO6_OK=0
fi
if printf '%s' "$OUT_JSON" | grep -qF "$SECRET"; then
  SCENARIO6_OK=0
fi
if ! printf '%s' "$OUT_JSON" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
names = [c.get("name") for c in data.get("checks", [])]
sys.exit(0 if "model-key" in names else 1)
' 2>/dev/null; then
  SCENARIO6_OK=0
fi
if [ "$SCENARIO6_OK" -eq 1 ]; then
  pass "密钥不出现在任何输出里，--json 可解析且含 model-key 检查项"
else
  fail "密钥不出现在任何输出里，--json 可解析且含 model-key 检查项"
fi

# ------------------------------------------------------------------ 场景 7
# 设置代理变量时 proxy 为 WARN 且退出码 0（防止组装说明文字时把变量名吃掉）
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  HTTP_PROXY="http://127.0.0.1:9"
if line_is "$(printf 'WARN\tproxy')" && [ "$RC" -eq 0 ]; then
  pass "设置代理变量时 proxy 为 WARN 且退出码 0"
else
  fail "设置代理变量时 proxy 为 WARN 且退出码 0"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 8
# 只设 endpoint、不设 id 时 model-env 为 FAIL 且退出码 1
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1"
if line_is "$(printf 'FAIL\tmodel-env')" && [ "$RC" -eq 1 ]; then
  pass "只设 endpoint 不设 id 时 model-env 为 FAIL 且退出码 1"
else
  fail "只设 endpoint 不设 id 时 model-env 为 FAIL 且退出码 1"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 9
# 只设小写 https_proxy 时 proxy 为 WARN
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  https_proxy="http://127.0.0.1:9"
if line_is "$(printf 'WARN\tproxy')" && [ "$RC" -eq 0 ]; then
  pass "只设小写 https_proxy 时 proxy 为 WARN"
else
  fail "只设小写 https_proxy 时 proxy 为 WARN"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 10
# 带用户信息的端点时 model-env 为 FAIL（F1 的例子）
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  MUYON_EVAL_MODEL_ENDPOINT="http://localhost:x@evil.example.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model"
if line_is "$(printf 'FAIL\tmodel-env')" && [ "$RC" -eq 1 ]; then
  pass "带用户信息的端点时 model-env 为 FAIL"
else
  fail "带用户信息的端点时 model-env 为 FAIL"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 11
# 假 curl 收到的请求为 GET <base>/models，且参数里没有密钥
ARGS_FILE="$TMP_DIR/curl-args.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" FAKE_CURL_CODE=200 \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1/chat/completions" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY="dummy-key-for-test"
ARGS_OK=1
if [ "$(tail -n 1 "$ARGS_FILE" 2>/dev/null)" != "https://api.example.com/v1/models" ]; then
  ARGS_OK=0
fi
if grep -qE -- '^(-X|-d|--data)' "$ARGS_FILE" 2>/dev/null; then
  ARGS_OK=0
fi
if grep -qF "dummy-key-for-test" "$ARGS_FILE" 2>/dev/null; then
  ARGS_OK=0
fi
if ! grep -qF "Bearer dummy-key-for-test" "${ARGS_FILE}.stdin" 2>/dev/null; then
  ARGS_OK=0
fi
if [ "$ARGS_OK" -eq 1 ]; then
  pass "假 curl 收到的请求为 GET <base>/models 且参数不含密钥"
else
  fail "假 curl 收到的请求为 GET <base>/models 且参数不含密钥"
  printf '    curl 参数:\n'
  sed 's/^/    /' "$ARGS_FILE" 2>/dev/null
  printf '    curl stdin:\n'
  sed 's/^/    /' "${ARGS_FILE}.stdin" 2>/dev/null
fi

# ------------------------------------------------------------------ 场景 12
# 无 scheme 的端点（: // 出现在路径里）为 FAIL 且不调用 curl
ARGS_FILE="$TMP_DIR/curl-args-12.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="127.0.0.2:18082/x://localhost/v1" \
  MUYON_EVAL_MODEL_ID="test-model"
S12_OK=1
if ! line_is "$(printf 'FAIL\tmodel-env')"; then
  S12_OK=0
fi
if [ "$RC" -ne 1 ]; then
  S12_OK=0
fi
if [ -f "$ARGS_FILE" ]; then
  S12_OK=0
fi
if [ "$S12_OK" -eq 1 ]; then
  pass "无 scheme 的端点（127.0.0.2:18082/x://localhost/v1）为 FAIL 且不调用 curl"
else
  fail "无 scheme 的端点（127.0.0.2:18082/x://localhost/v1）为 FAIL 且不调用 curl"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 13
# 非 http(s) 端点（ftp://）为 FAIL 且不调用 curl
ARGS_FILE="$TMP_DIR/curl-args-13.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="ftp://localhost/v1" \
  MUYON_EVAL_MODEL_ID="test-model"
S13_OK=1
if ! line_is "$(printf 'FAIL\tmodel-env')"; then
  S13_OK=0
fi
if [ "$RC" -ne 1 ]; then
  S13_OK=0
fi
if [ -f "$ARGS_FILE" ]; then
  S13_OK=0
fi
if [ "$S13_OK" -eq 1 ]; then
  pass "非 http(s) 端点（ftp://localhost/v1）为 FAIL 且不调用 curl"
else
  fail "非 http(s) 端点（ftp://localhost/v1）为 FAIL 且不调用 curl"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 14
# 密钥含换行时为 FAIL、不调用 curl 且输出不含密钥
ARGS_FILE="$TMP_DIR/curl-args-14.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY=$'sk-line1\nsk-line2'
S14_OK=1
if ! line_is "$(printf 'FAIL\tmodel-key')"; then
  S14_OK=0
fi
if [ "$RC" -ne 1 ]; then
  S14_OK=0
fi
if [ -f "$ARGS_FILE" ]; then
  S14_OK=0
fi
if printf '%s' "$OUT" | grep -qF "sk-line1"; then
  S14_OK=0
fi
if [ "$S14_OK" -eq 1 ]; then
  pass "密钥含换行时为 FAIL、不调用 curl 且输出不含密钥"
else
  fail "密钥含换行时为 FAIL、不调用 curl 且输出不含密钥"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 15
# 本机端点（有密钥）：参数含 --noproxy 和 *，URL 为 <base>/models
ARGS_FILE="$TMP_DIR/curl-args-15.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" FAKE_CURL_CODE=200 \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="http://localhost:11434/v1/chat/completions" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY="dummy-key-for-test"
S15_OK=1
if ! grep -qxF -- "--noproxy" "$ARGS_FILE" 2>/dev/null; then
  S15_OK=0
fi
if ! grep -qxF -- "*" "$ARGS_FILE" 2>/dev/null; then
  S15_OK=0
fi
if [ "$(tail -n 1 "$ARGS_FILE" 2>/dev/null)" != "http://localhost:11434/v1/models" ]; then
  S15_OK=0
fi
if [ "$S15_OK" -eq 1 ]; then
  pass "本机端点（有密钥）请求 <base>/models 且带 --noproxy *"
else
  fail "本机端点（有密钥）请求 <base>/models 且带 --noproxy *"
  printf '    curl 参数:\n'
  sed 's/^/    /' "$ARGS_FILE" 2>/dev/null
fi

# ------------------------------------------------------------------ 场景 16
# 本机端点（无密钥）：参数含 --noproxy 和 *、无 -K，URL 为 <base>/models
ARGS_FILE="$TMP_DIR/curl-args-16.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" FAKE_CURL_CODE=200 \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="http://localhost:11434/v1/chat/completions" \
  MUYON_EVAL_MODEL_ID="test-model"
S16_OK=1
if ! grep -qxF -- "--noproxy" "$ARGS_FILE" 2>/dev/null; then
  S16_OK=0
fi
if ! grep -qxF -- "*" "$ARGS_FILE" 2>/dev/null; then
  S16_OK=0
fi
if [ "$(tail -n 1 "$ARGS_FILE" 2>/dev/null)" != "http://localhost:11434/v1/models" ]; then
  S16_OK=0
fi
if grep -qxF -- "-K" "$ARGS_FILE" 2>/dev/null; then
  S16_OK=0
fi
if [ "$S16_OK" -eq 1 ]; then
  pass "本机端点（无密钥）请求 <base>/models、带 --noproxy * 且无 -K"
else
  fail "本机端点（无密钥）请求 <base>/models、带 --noproxy * 且无 -K"
  printf '    curl 参数:\n'
  sed 's/^/    /' "$ARGS_FILE" 2>/dev/null
fi

# ------------------------------------------------------------------ 场景 17
# localhost.evil.com 按远程处理并 FAIL（需要 HTTPS）
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  MUYON_EVAL_MODEL_ENDPOINT="http://localhost.evil.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model"
if line_is "$(printf 'FAIL\tmodel-env')" && [ "$RC" -eq 1 ]; then
  pass "localhost.evil.com 按远程处理并 FAIL"
else
  fail "localhost.evil.com 按远程处理并 FAIL"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 18
# [::1] 端点判为本机并 OK
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" \
  MUYON_EVAL_MODEL_ENDPOINT="http://[::1]:8080/v1" \
  MUYON_EVAL_MODEL_ID="test-model"
if line_is "$(printf 'OK\tmodel-env\t本机端点已配置')" && [ "$RC" -eq 0 ]; then
  pass "[::1] 端点判为本机并 OK"
else
  fail "[::1] 端点判为本机并 OK"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ 场景 19
# 密钥转义：sk-a"b\c 经 stdin 传递（转义形式或等价原文）
ARGS_FILE="$TMP_DIR/curl-args-19.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" FAKE_CURL_CODE=200 \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY='sk-a"b\c'
S19_OK=0
if grep -qF 'Bearer sk-a\"b\\c' "${ARGS_FILE}.stdin" 2>/dev/null; then
  S19_OK=1
fi
if grep -qF 'Bearer sk-a"b\c' "${ARGS_FILE}.stdin" 2>/dev/null; then
  S19_OK=1
fi
if [ "$S19_OK" -eq 1 ]; then
  pass "密钥转义后经 stdin 传递"
else
  fail "密钥转义后经 stdin 传递"
  printf '    curl stdin:\n'
  sed 's/^/    /' "${ARGS_FILE}.stdin" 2>/dev/null
fi

# ------------------------------------------------------------------ 场景 20
# 端点末尾带 /：请求 https://api.example.com/v1/models
ARGS_FILE="$TMP_DIR/curl-args-20.txt"
rm -f "$ARGS_FILE" "$ARGS_FILE.stdin"
run_doctor "" FAKE_FLUTTER_VERSION="$EXPECTED_FLUTTER" FAKE_CURL_CODE=200 \
  FAKE_CURL_ARGS_FILE="$ARGS_FILE" \
  MUYON_EVAL_MODEL_ENDPOINT="https://api.example.com/v1/" \
  MUYON_EVAL_MODEL_ID="test-model" \
  MUYON_EVAL_MODEL_KEY="dummy-key-for-test"
if [ "$(tail -n 1 "$ARGS_FILE" 2>/dev/null)" = "https://api.example.com/v1/models" ]; then
  pass "端点末尾斜杠被正确剥离"
else
  fail "端点末尾斜杠被正确剥离"
  printf '    curl 参数:\n'
  sed 's/^/    /' "$ARGS_FILE" 2>/dev/null
fi

# ------------------------------------------------------------------ 汇总
if [ "$FAILED" -gt 0 ]; then
  printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
  exit 1
fi
printf 'all %d scenarios passed\n' "$PASSED"
exit 0
