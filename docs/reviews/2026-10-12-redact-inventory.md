# 脱敏实现盘点（B17）

- 日期：2026-10-12；分支 `task/b17-redact-inventory-20261012`；基线 `8086ad2d`（最新 develop）。
- 范围：`apps/muyon/lib`、`packages/*/lib` 的源代码（只读盘点，未改任何代码）。
- 检索命令：`grep -rli redact apps/muyon/lib packages/*/lib`；`grep -rli sanitiz ...`；`grep -rli mask ...`，及逐函数 `grep -rn` 调用方。

## 1. 命中文件

- redact：19 个文件；sanitiz：0 个；mask：13 个；去重后 26 个。
- 分类：
  - **真脱敏实现/落点**（12）：`credential_redaction.dart`、`mcp_adapter.dart`、`outbound_tool_ledger.dart`、`model_gateway.dart`、`mcp_servers_page.dart`、`ontology_card_snapshot.dart`、`agent_compaction_flow.dart`、`agent_eval_run.dart`、`agent_model_turn.dart`、`personal_agent.dart`、`agent_dispatch.dart`、`qa_service.dart`（后 5 个是 `redactCredentials` 调用点）。
  - **仅调用/转发**：`llm_selection_eval.dart`（再导出 + 调用）、`dream_service.dart`、`agent_eval.dart`（import，供 part 使用）、`platform_shell.dart`（import，供 part `platform_shell_personal.dart:135` 使用）、`inquiry_plugin.dart`、`research_tools_page.dart`。
  - **仅注释**：`tool_registry.dart:632`、`model_provider.dart:405`、`section_delete_preview.dart:59`、`inquiry_readonly_snapshot.dart:28`、`agent_dispatch.dart:38`。
  - **非脱敏误报**：`transfer_service.dart:1363-1364`（CRC 位掩码）、`spec_parse.dart:219-227`（用 `\u0000` 遮蔽已解析片段）、`lan.dart:480-481`（netmask 注释）。

## 2. 脱敏函数 / 规则明细

净脱敏输出函数 6 个 + 字段级遮盖 1 个；凭据识别辅助 3 个；可发送性校验 2 个（相邻，不是输出脱敏）。

| # | 文件:行 | 函数 / 规则 | 输入 | 处理模式 | 输出 | 调用方（核过） |
|---|---|---|---|---|---|---|
| 1 | `services/models/credential_redaction.dart:27` | `redactCredentials(Object error, {String? secret})` | 任意 error / 字符串；可选已用密钥 | ①按值替换 `secret`（≥8 字符）②文本仍含 `bearer|authorization`（忽略大小写）则整段清空为固定文案 | `<redacted>` 或 `'<Type>: details withheld (may contain the credential)'` | assistant 7 处（`agent_eval_run:172,277`、`agent_model_turn:239`、`llm_selection_eval:287`、`qa_service:284`、`agent_dispatch:227`、`dream_service:141`、`personal_agent:732`）、`mcp_adapter:343`、`outbound_tool_ledger:86,156`、`mcp_servers_page:155,215,262,484`、`model_gateway:768` |
| 2 | `credential_redaction.dart:43` | `maskSecret(String text, String? secret)` | 文本 + 密钥 | 仅按值替换（≥8 字符），不做关键词规则 | `<redacted>` | `mcp_adapter:122,176,233,236,269`、`model_gateway:175`（经 `gateway.mask` 再到 `agent_compaction_flow:477`） |
| 3 | `credential_redaction.dart:21` | `mayContainCredential(String)` | 文本 | 关键词检测 | bool | 仅 `redactCredentials:34`（无外部调用） |
| 4 | `credential_redaction.dart:11 / 18 / 12` | `_credentialMention` / `minRedactedSecretLength=8` / `_visibleAscii` | — | 规则/常量 | — | 同文件；`minRedactedSecretLength` 另被 `mcp_adapter` 注释引用 |
| 5 | `credential_redaction.dart:50` | `isSendableCredential(String)` | 文本 | 校验（可见 ASCII，无空格/换行/全角），非脱敏 | bool | `inquiry_plugin:422`、`research_tools_page:343`、`mcp_adapter:428`、`mcp_servers_page:440`、`platform_shell_personal:135`、`model_gateway:683` |
| 6 | `platform/mcp_adapter.dart:45-53` | `_credentialParams`（20+ 参数名集合） | — | 自定义字段名清单：`api_key/apikey/api-key/key/token/access_token/auth/authorization/secret/client_secret/password/pass/sig/signature/passwd/x-api-key/access_key/accesskey/private_key/jwt` | — | 经 `isCredentialParam` |
| 7 | `mcp_adapter.dart:57 / 60` | `_camelKey` / `isCredentialParam(String)` | query 参数名 | 集合命中 ∪ `[_-]key$` ∪ camelCase `...Key` ∪ 包含 `token/secret/password/apikey` | bool | `isCredentialParam` 被 `:88,:99,:120` 调用 |
| 8 | `mcp_adapter.dart:86` | `credentialParamNames(Uri)` | URL | 列出凭据参数名（识别辅助，不脱敏） | `List<String>` | `mcp_servers_page:469`（保存时提示"会以明文保存"） |
| 9 | `mcp_adapter.dart:94` | `maskedEndpoint(Uri, {String mask='••••'})` | URL | 仅替换 query 中凭据参数的值，URL 其余原样 | 默认 `••••`；调用方可传 `<redacted>` | `redactEndpoint:117`、`outbound_tool_ledger:61`（**持久化前**）、`mcp_servers_page:322`（展示） |
| 10 | `mcp_adapter.dart:114` | `redactEndpoint(String text, Uri endpoint)` | 错误文本 + URL | 先把文本中整个 URL 重写为 `maskedEndpoint('<redacted>')`；再对凭据参数值（原样与解码两种形态）按 `maskSecret` 替换 | `<redacted>` | `mcp_adapter:344`、`outbound_tool_ledger:157`、`mcp_servers_page:216,262,484` |
| 11 | `mcp_adapter.dart:335,339` | `token` + `_redacting<T>` | MCP 调用 | 包裹 `initialize`/`rpc`：错误先 `redactEndpoint`，再 `redactCredentials(secret: token)` | 安全错误文本 | `:358`（initialize）、`:370`（rpc） |
| 12 | `mcp_adapter.dart:232` | `_maskTree(Object?, String?)` | 解码后的 JSON 结构 | 递归替换 map 的 key 与 value、list、string（防转义后漏替） | 同构结构 | `:281`（`tools/call` 的 `structuredContent` 进结果前） |
| 13 | `mcp_adapter.dart:176 / 269 / 220` | 工具描述脱敏 / 结果文本脱敏 / `skipped` | 远端 tools 列表、结果文本、注册错误 | `:176` `maskSecret(描述, token)`；`:269` `maskSecret(结果文本, token)`（进 summary/receipt 前）；**`:220` `skipped[name]='$error'` 未脱敏，`:366-372` UI 直接展示** | — | 注册流程 / `_call` / `mcp_servers_page` |
| 14 | `services/models/model_gateway.dart:172` | `OpenAiModelGateway.mask(profile, text)` | 文本 + profile | 读 secret store 后 `maskSecret` 按值替换（用于持久化前的模型输出，如压缩摘要） | 替换后文本 | `agent_compaction_flow:477` |
| 15 | `model_gateway.dart:768` | 失败收敛（`fail(error)`） | 任意 error | `redactCredentials(error, secret: _usedCredential)`，再写入 outbound 记录并抛出安全文本 | 安全错误 | 网关内部失败路径（`:766` 注释） |
| 16 | `platform/outbound_tool_ledger.dart:45-61 / 86 / 156` | `begin` / `finish` / `runDigest` catch | 目标 URL、错误 | `begin` 只取 scheme/host/port/path 再 `maskedEndpoint`（**持久化前**）；`finish` 错误经 `redactCredentials`；catch 经 `redactCredentials(redactEndpoint(...), secret:)` | 脱敏后的 destination/error 落库 | 台账自身 |
| 17 | `screens/mcp_servers_page.dart:155,215-216,262,484 / 322 / 440 / 469` | 页面错误与展示 | Playground/UI 错误、URL、token | 展示前 `redactCredentials(+redactEndpoint)`；`maskedEndpoint` 展示地址；`isSendableCredential` 校验；`credentialParamNames` 提示 | 页面文本 | UI |
| 18 | `assistant/ontology_cards/ontology_card_snapshot.dart:115-134` | `_projectField`（字段级遮盖） | `OntologyFieldSpec` + 快照事实 | `sensitivity != none` 的字段一律显示 `'已遮盖'`（`masked: true`），不按凭据/key 判定 | `OntologyCardField(masked)` | `inquiry_ui_planning_source:104`（→ `FactState.notDisclosed`）；其余渲染消费链未逐一跟踪 |
| 19 | `assistant/agent_eval/agent_eval_environment.dart:21 / 47` | 私有 `_visibleAscii` | env 中的 eval key | 与 `credential_redaction.dart:12` **重复定义**；非法时抛 `ArgumentError`（不回显值） | bool / 异常 | eval 环境构造 |

## 3. 重复 / 不一致（6 条）

1. **`_visibleAscii` 重复定义**：`credential_redaction.dart:12` 与 `agent_eval_environment.dart:21` 同规则两处维护；前者配合 `invalidCredentialMessage` 常量，后者自抛 `ArgumentError`。
2. **按值替换重复**：`redactCredentials` 的内联替换（`credential_redaction.dart:31-33`）与 `maskSecret`（`:43-46`）逻辑相同（同 8 字下限、同 `<redacted>`），未复用。
3. **凭据形态识别两套体系**：`mcp_adapter` 有参数名清单 + `[_-]key$` + camelCase `...Key` + contains 规则；`credential_redaction` 只有 `bearer|authorization` 关键词。`sk-...` 形态在 lib 内**无任何专门正则**；`--api-key` CLI 形态无处理；通用错误路径不识别 `api_key=`/`token=` 等 query 名（只有 MCP 路径识别）。
4. **脱敏时机分层**：持久化前（ledger `begin/finish`、MCP 结果进 receipt、assistant 错误进 task/通知）vs 展示时（`mcp_servers_page`）vs 渲染时字段级（ontology card）；`mcp_adapter:220` 的 `skipped` 错误在 UI 直接展示、无任何遮罩（`:366-372`）。
5. **占位符不统一**：`<redacted>`（值替换与 `redactEndpoint`）与 `••••`（`maskedEndpoint` 默认值，仅 UI 展示）。
6. **覆盖差异**：未见邮箱、路径的专门规则；query 凭据值遮罩仅在 MCP 适配器使用，通用 `redactCredentials` 路径不含该规则。

## 4. 合并建议（不实施）

把「按值替换（`maskSecret`）+ 关键词兜底（`redactCredentials`）+ query 参数名识别（`isCredentialParam`/清单/后缀规则）」三套规则收敛到 `credential_redaction.dart`（若保留 mcp 专用语义可换更中性的模块名），`mcp_adapter` 与之互相引用、去掉 `agent_eval_environment.dart` 的重复正则；`maskedEndpoint` 的占位符参数化（`••••`/`<redacted>`）与 ontology 字段级 `sensitivity` 遮盖保留为独立语义，不强行统一；`skipped` 展示路径接入 `redactCredentials` 需先确认其错误来源。

## 5. 未确认

- `mcp_adapter:220` 的 `skipped` 值为注册期异常文本（本次未穷举 `registry.register` 全部抛错来源），是否可能引用凭据 → **未确认**。
- `sk-` 形态、`--api-key`、邮箱、路径是否需要脱敏属产品决策，本轮只记录现状 → **未确认**。
- ontology 字段级 `masked` 的完整 UI 消费链仅确认 `inquiry_ui_planning_source:104` 一处，卡片渲染侧未逐一跟踪 → **未确认**。
- `agent_dispatch.dart:38` 注释所述 "masked card" 对应流程未展开核对 → **未确认**（仅注释）。
