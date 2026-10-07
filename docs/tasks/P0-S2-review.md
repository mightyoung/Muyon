# P0-S2 审查

审查分支 `review/P0-S2` @ `de813af`（senior 的 `9c04009` + leader 合入最新 develop）· 核实：`reviewer-sonnet-high` · 2026-10-07

## 范围
4 个文件：`mcp_adapter.dart`、`mcp_servers_page.dart`、`credential_redaction.dart`（只新增 `maskSecret`）、`mcp_token_redaction_test.dart`（新增）。没有修改已有测试。

## 核实结果
| 项 | 结论 |
|---|---|
| 没有削弱 P0-S1 | 满足：R1 固定错误文本、R4 的 8 字符下限、`bearer/authorization` 关键词规则、`invalidCredentialMessage`、`isSendableCredential` 都没有改动；P0-S1 的既有测试全部通过；把 R4 下限改成 4，`credential_redaction_test` 失败 |
| 1 复用共享脱敏函数 | 满足 |
| 2 提前校验令牌 | 满足：发请求之前校验；Tab、非 ASCII、前导空格、结尾 `\n`、空串，请求数都是 0 |
| 3 脱敏所有对外错误文本 | **部分满足**，见 F2、F4 |
| 4 保存时拒绝 | 满足：不修剪，不写入存储，不回显 |
| 5 排查其他凭据 | 满足（URL 查询参数里的令牌已披露为「未处理」，见 F3） |
| 运行 | `flutter analyze` 没有问题；`mcp_token_redaction_test` `+6`；宿主全量 `+450 ~2`，全部通过 |

## 结论

### 阻断
**F1 `structuredContent` 回显的令牌没有脱敏，会发给云端模型。** `mcp_adapter.dart:142-146` 把 `data['structured']` 原样放进 `ToolCallResult`。核实者用回环 MCP 服务器加脚本网关，跑通完整助手链路，确认令牌会进入以下位置（19 字符和 164 字符的令牌都会）：
- 工具回执 `tool_invocation_receipts.result_json`；
- 任务 payload；
- 发给模型的第二次请求体（`personal_agent.dart:596-597` 的 `trustedToolResult` 用的是 `result.toJson()`）。

这和提交说明里「工具结果回显令牌：已处理」不符。
- 修法：对 `structured` 做同样的值替换（例如 `jsonDecode(maskSecret(jsonEncode(structured), token))`）；保证不了安全时就不要放进 `data`。
- 测试：服务器在 `structuredContent` 里回显令牌，断言 `result.toJson()` 和回执里都没有令牌。

### 应改
**F2 长令牌遇到非 JSON 响应体时，会泄漏前缀。**
- 位置：`mcp_adapter.dart:272`（`jsonDecode(body)`）和 `:287`（SSE `data:`）。
- 问题：`FormatException.toString()` 会引用响应体，只引用约 75 个字符，所以完整令牌的值替换匹配不上。用 164 字符令牌复现时，错误文本里出现了令牌的前约 63 个字符，这和 P0-S1 的 R1 是同一类问题。
- 修法：和网关一样，解析失败时抛固定错误（例如 `FormatException('mcp_response_not_json')`），不引用响应体。
- 测试：用 ≥80 字符的令牌，断言错误文本里不出现令牌的任何 12 字符片段。

**F4 有 5 处脱敏，删掉后测试仍然全绿。**
- 值替换路径：第 168-182 行的用例回显的是 `rejected Bearer …`，只靠关键词规则就整条隐藏了，`secret:` 值替换从来没有被单独测到。改法：回显不带 `Bearer` 的纯令牌，断言结果含 `<redacted>`。
- 页面上读取、移除、保存三处错误的脱敏：各补一个用例，让测试仓库抛出带令牌的异常。
- `notifications/initialized` 外层的 `_redacting`：让服务器对这条通知返回回显令牌的错误。

### 需要用户决定（不阻塞本轮）
**F3 URL 查询参数里的令牌**（如 `?api_key=`）：
- 会在卡片上明文显示（`mcp_servers_page.dart:319`），并存入设置（`:46`）；
- 连接中途断开时，`HttpException` 的 `uri =` 也会带上它，页面会直接显示。

可选做法有三种：遇到敏感参数名时提示；显示和存储前遮盖参数值；接受现状并在文档里写明。

### 只记录
- 7 字符以内的令牌不会被脱敏，这是 R4 的设计下限。
- base64、URL 编码等变形后的回显没有覆盖。
- `_redacting` 会把异常类型统一改成 `StateError`，行为上无害。

## 处理
退回 senior：在 `review/P0-S2` 上修 F1（阻断）、F2、F4，提交并推送，回报附 analyze、宿主全量，以及每处新守护对应的变异结果。复审派 `reviewer-sonnet-high`。

---

## 第二轮（2026-10-07，云端 Sonnet 子代理修复）

senior 未开始修复；用户指示改由云端 Sonnet 5.5 子代理修复（ADR-0001 后续记录）。F3 由 leader 按用户授权决定：**显示与错误文本遮盖、保存时不阻塞提示、存储不变**。

| 提交 | 内容 |
|---|---|
| `4645fbb` | F1：`structuredContent` 脱敏；F2：非 JSON 响应体固定为 `mcp_response_not_json`；F4：5 处脱敏各补守护 |
| `915a366` | F3：凭据类查询参数在卡片上显示为 `••••`，连接 / 移除 / 保存 / 适配器错误文本替换为 `<redacted>`，保存时 SnackBar 提示，存储不变 |
| `df29420` | R1：`structuredContent` 改为递归遍历替换（含键），不再先序列化；O1：参数名补 `passwd`、`x-api-key`、`access_key`、`private_key`、`jwt` 及 `_key` / `-key` / 驼峰 `Key` 后缀；O2：`tools/list` 描述注册前脱敏 |

### 核实（独立 Sonnet 子代理，两轮）
| 项 | 结论 |
|---|---|
| 范围 | `mcp_adapter.dart`、`mcp_servers_page.dart`、`credential_redaction.dart`（仅 P0-S2 首轮新增 `maskSecret`）、测试与本文件；没有修改已有测试 |
| F1 端到端探针 | 回环 MCP 服务器 + 脚本网关 + 完整 `PersonalAgent` 链路；服务器在文本、`structuredContent` 值 / 嵌套值 / 键、工具描述中回显令牌；扫描第二次模型请求体、整个 sqlite 库、注册表描述，按 12 字符窗口检查原文、JSON 转义一次 / 两次。164 字符令牌与含 `"`、`\` 的 41 字符令牌**全部 0 命中**（第一轮后者曾泄漏，即 R1） |
| F2 | ≥80 字符令牌，JSON 与 SSE 两种非 JSON 响应体，错误文本无任何 12 字符片段 |
| 变异 | 共 14 处（F1、R1、F2、F4 五处、F3 卡片 / 连接错误 / 保存提示、O1、O2），删除后均有测试失败 |
| P0-S1 | `credential_redaction.dart` 已有逻辑未改，相关测试通过 |
| 运行 | `flutter analyze` 无问题；宿主全量 `+473 ~2: All tests passed!`；`mcp_token_redaction_test` +23 |

### 已知限制（记录，不阻塞）
- 地址查询参数里的凭据仍以明文保存在工作区设置 `mcpServers`，编辑对话框显示原值，请求时随 URL 发出；遮盖只覆盖页面显示与错误文本，按配置值（≥8 字符）与完整 URL 匹配，被服务器或代理改写形式（base64、重新编码）的值匹配不到。改存系统安全存储需要改存储结构，排到第二阶段可选项。
- 参数名匹配是启发式：`X-Amz-Signature` 一类带前缀的签名参数仍不遮；`tokenizer` 会被多遮（无害）。
- 工具 `inputSchema` 中回显令牌未脱敏（与 O2 同类，可能性更低）。
- `McpServersPage._readServers` 在首次 build 中设置 `error`，读取失败的提示要到下一次重建才显示（界面缺陷，不是泄漏）。

## 结论（第二轮）
**合入。** F1（阻断）已修复并经端到端探针确认；F2、F3、F4、R1、O1、O2 均有测试与变异守护。上面四条限制转入第二阶段可选项。
