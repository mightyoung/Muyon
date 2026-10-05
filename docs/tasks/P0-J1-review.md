# P0-J1 审查结论

审查对象：`task/p0-j1-env-doctor` @ `896c45f` · 审查：leader（代码核实由 Sonnet 子代理执行）· 日期：2026-10-06

**结论：修复后合并。** 没有阻断项。下文 F1～F3 三项应改需要本轮修复；可选项中 F4～F6 建议顺手修改；F7～F9 只做记录，不要求修改。

## 范围
`43c408c..896c45f` 只新增 `scripts/doctor.sh`（287 行）与 `scripts/test_doctor.sh`（187 行），均为可执行文件，没有改动其他文件。✅

## 交付核对
说明里的每一项都已满足：输出格式、退出码、`--json` 结构、8 项检查的顺序与判定，6 个必需测试场景另加 1 个代理场景，不写文件，只请求 `GET <base>/models`。其中 `model-env` 有一处绕过，见 F1。

## 核实结果（子代理在 Linux 上重跑）
- `bash -n` 两个文件均通过。
- `bash scripts/test_doctor.sh`：7 个场景全部 PASS，退出码 0，与提交说明一致。
- `doctor.sh`、`doctor.sh --json` 能正常运行；JSON 可以解析，键名与计数正确。
- 机器上没有 shellcheck，未运行。
- bash 3.2 不兼容写法：检查没有命中，但只在 bash 5.2 上实际运行过。
- 用真实 curl 对本机服务器验证：只发出 `GET /v1/models`，密钥只出现在请求头中，stdout、stderr 都不含密钥。

## 必须修复（应改）

### F1 回环判定可被 URL 中的用户信息绕过（`doctor.sh:179-187`）
`http://localhost:x@evil.example.com/v1`、`http://127.0.0.1:80@evil.example.com/v1` 会被判为本机端点，于是 `model-env`、`model-key` 都通过，密钥随后以明文 http 发往 `evil.example.com`。

**修复：**
1. 取出 authority：`auth=${ep#*://}; auth=${auth%%[/?#]*}`。
2. 含 `@` 时直接判 `FAIL model-env`，说明写「端点不应包含用户信息」。
3. 去掉端口后，对 host 做精确匹配，只接受 `localhost`、`127.0.0.1`、`[::1]`。
4. `localhost.evil.com` 必须判为远程。

### F2 密钥出现在 curl 的命令行参数里（`doctor.sh:231-232`）
请求进行期间，本机其他用户能通过 `ps` 看到 `Authorization: Bearer <密钥>`。

**修复：** 通过标准输入把配置交给 curl，密钥就不会进入命令行参数：
```bash
esc=$(printf '%s' "$MODEL_KEY" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf 'header = "Authorization: Bearer %s"\n' "$esc" \
  | curl -sS -o /dev/null -w '%{http_code}' --max-time 10 -K - "$MODELS_URL"
```
没有密钥时不传 `-K -`。

### F3 测试缺口（`test_doctor.sh`）
变异测试显示，以下错误改动测试抓不到：`--json` 不输出任何内容、不剥离 `/chat/completions`、curl 改用 POST、不检查小写代理变量、只设一个模型变量却不报 FAIL。需要补充：
1. 场景 6 的 `--json` 部分：断言输出能被 `python3 -c 'import json,sys; json.load(sys.stdin)'` 解析，并且包含名为 `model-key` 的检查项。
2. 假 curl 把收到的参数逐行写入临时文件，测试断言三点：
   - 请求的 URL 是 `<base>/models`（端点为 `.../v1/chat/completions` 时，应请求 `.../v1/models`）；
   - 参数里没有 `-X`、`-d`、`--data`；
   - F2 修复后，参数里不出现密钥。
3. 新增场景：只设 `MUYON_EVAL_MODEL_ENDPOINT` 不设 `MUYON_EVAL_MODEL_ID` 时，`model-env` 为 FAIL、退出码为 1。
4. 新增场景：只设小写 `https_proxy` 时，`proxy` 为 WARN。
5. 新增场景：带用户信息的端点（F1 的例子）时，`model-env` 为 FAIL。

## 建议顺手修改（可选）
- **F4**：端点是回环地址时，给 curl 加 `--noproxy '*'`，避免本机请求连同密钥经代理转发。
- **F5**：先去掉端点末尾的 `/`，再剥离 `/chat/completions`，避免得到 `/v1//models`。
- **F6**：解析 `flutter devices --machine` 时，从第一个 `[` 开始读取，容忍前面的非 JSON 输出。脚本开头检查是否有 `python3`，缺少时给出明确提示，不要让 `--json` 静默无输出。

## 只记录
- **F7**：`model-env` 为 FAIL 时，`model-key` 直接 SKIP。说明对此没有规定，保持现状。
- **F8**：scheme 区分大小写，`HTTPS://` 会判 FAIL。属于预期的严格行为。
- **F9**：`line_is` 是子串匹配。目前不会误判。

## 修复方式
1. 执行者（junior）检出 `review/P0-J1`，只修改上面两个脚本，提交并推送到该分支。
2. 修复后重跑 `bash -n` 与 `bash scripts/test_doctor.sh`，贴出完整输出；本机有 shellcheck 时一并运行。
3. leader 派子代理复核后合入 `develop`。合入时只挑本任务自己的提交，不带入分支起点上的草稿。

---

## 复核（2026-10-06，`b69b72f`，Sonnet 子代理）

**结论：通过，合入 `develop`。**

- **范围**：本轮只改了两个脚本（+176/−36 行）。
- **F1 已修复**：带用户信息的端点一律判 FAIL，报错不会回显用户信息；主机名改为精确匹配，`localhost.evil.com` 和 `127.0.0.1.evil.com` 按远程处理；`localhost`、`127.0.0.1`、`[::1]`，带不带端口都按本机处理。
- **F2 已修复**：用真实 curl 测试，请求进行中做了 25 次 `ps` 快照，参数里都没有密钥；服务器收到的 `Authorization` 与密钥逐字节一致，含 `"`、`\`、`$()`、UTF-8 等字符也一样。没有密钥时不传 `-K -`。
- **F3 已修复**：新增场景 8～11，测试共 11 项全部通过；上一轮测试没抓到的 7 类错误改动现在都能抓到。
- **F4～F6 已实现**：
  - 本机请求带 `--noproxy '*'`；
  - 端点末尾的 `/` 会先去掉；
  - 设备列表从第一个 `[` 开始解析；
  - 缺少 python3 时给出明确提示。
- **回归**：`bash -n` 通过；shellcheck 0.11.0 检查 `doctor.sh` 无告警，`test_doctor.sh` 只有两条 info 级提示；12 组密钥泄露检查全部为零。

### 留给后续任务 P0-J2 的问题（安全加固，冻结期允许）

1. **没有 scheme 的端点可以伪装成本机地址**（`doctor.sh:191-195`）。`${EP_AUTH#*://}` 会剥到字符串中第一个出现的 `://`，所以 `host:port/x://localhost/v1` 会被判为本机，curl 随后以明文 http 把密钥发给真实主机，已用真实 curl 复现。
2. **密钥中的换行可以注入 curl 配置**（`doctor.sh:263,271`），可以多发一个请求并带上密钥，已复现。
3. **测试缺口**：
   - 本机两条 curl 调用没有参数断言；
   - 精确主机匹配、`-K` 转义、F4 和 F5 都没有测试。

以上两处都要先控制环境变量才会被利用，风险低，不阻断本次合入。
