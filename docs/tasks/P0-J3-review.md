# P0-J3 审查

审查分支 `review/P0-J3` @ `44f5cc3`（junior）· 核实：`reviewer-sonnet-low` · 2026-10-07

## 范围
只改 `scripts/doctor.sh`（读取方式 1 行，加 2 行注释）和 `scripts/test_doctor.sh`。

## 逐项核对
| 条 | 结论 |
|---|---|
| 1 场景 19 精确匹配 | 满足：用 `grep -qxF` 匹配整行，未转义写法的可选匹配已删 |
| 2 场景 14 CR/CRLF/LF | 满足：3 种密钥 × 远程、本机共 6 组，每组断言 FAIL、退出码 1、curl 没被调用、输出不含密钥 |
| 3 保留末尾换行 | 满足：`doctor.sh:180` 改为 `${MUYON_EVAL_MODEL_KEY-}`；新增场景 21（末尾 LF 判 FAIL） |
| 4 参数断言（可选） | 5 项都做了：新增 `curl_args_ok`（`--proto`、`--url`、禁止 `-X/-I/-H/-d`、远程请求不带 `--noproxy`），场景 22（URL 里带用户名密码）、场景 23（`/chat/completions/` 结尾） |
| 运行 | `bash -n` 通过；`test_doctor.sh` 输出 `all 23 scenarios passed`，退出码 0；Actions run 37552896323 success |

## 变异（全部被抓住）
- 读取方式改回 `$(printenv)` → 场景 21 失败。
- CR 检查削弱 → 场景 14 失败。
- LF 检查削弱 → 场景 14、21 失败。
- 引号或反斜杠不转义 → 场景 19 失败。
- 去掉 `--proto` → 6 个场景失败。
- 远程请求也带 `--noproxy` → 4 个场景失败。

## 可选（记录，不处理）
- `curl_args_ok` 用前缀匹配 `^(-X|-I|-H|-d|--data)`，以后如果加了 `-d` 开头的合法参数会误报。
- 本机没有 shellcheck，`-S warning` 没有验证；任务说明本来就写的是「有则跑」。
- CI（`scripts/ci.sh`）不跑 `test_doctor.sh`，自检脚本的回归只能靠手动跑。

## 结论
**合入。** 按 P0-J3 说明，自检脚本到此收口。
