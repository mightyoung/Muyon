# 实际适配器与日志出口核查

核查基线：`6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa`（2026-10-18）。本次为静态只读证据；没有运行实际 Dart 适配器，没有生产零泄漏结论。未找到仓库/父目录 `AGENTS.md` 或仓库 `.agents`；`/workspace/.agents` 为空。未执行任何 I04 旧 script 状态→HTTP 操作。

## 实际路径与现有保护

| 路径 | 固定基线源码证据 | 已有覆盖（本次未运行） |
| --- | --- | --- |
| 生成，非流式 | `apps/muyon/lib/services/models/model_gateway.dart:191–236,305–359`，`chat → request → _GatewayChannel` | `apps/muyon/test/outbound_ledger_test.dart:81–111,128–139`：实际网关 + loopback 服务验证生成/embedding 发出账本与 HTTP 失败 |
| 生成，流式/兼容解码 | `apps/muyon/lib/services/models/openai_compat_provider.dart:113–176,179–313`；网关 `:475–507` | `openai_compat_provider_test.dart`：有效文字、工具、截断、错误和不回显 endpoint 内容；`model_stream_ledger_test.dart:475–522`：provider error、畸形流及 HTTP 错误正文中的合成凭据不进入账本错误 |
| embedding | `model_gateway.dart:248–302`；`apps/muyon/lib/services/knowledge/embedding_service.dart:34–110`：输入校验、批量网关调用、事务落向量 | `outbound_ledger_test.dart:92–110`：成功调用账本元数据。不是完整 success/failure 正文 canary 矩阵 |
| 持久账本 | `apps/muyon/lib/platform/outbound_ledger.dart:17–35,69–97`：摘要、大小、目标、状态；无请求正文列 | 已有摘要/大小断言；不应重复修哈希保护 |
| 错误正文保护 | `model_gateway.dart:333–343`：JSON 解析错误改为固定代码；`:721–722`：HTTP 错误只保留状态；`openai_compat_provider.dart:132–134,283–291`：provider/畸形流固定代码 | `credential_redaction_callers_test.dart:156–194`：长合成凭据及其 12 字符片段不进入实际网关抛错/账本；`credential_redaction_test.dart`：header 错误及凭据脱敏 |
| 数据去向展示 | `apps/muyon/lib/screens/data_flow_page.dart:24–34`：读取账本；`outbound_ledger.dart:155–162`：返回所有列（包括 error） | 这是 UI 展示，不是诊断日志导出 |

凭据脱敏与正文不留存是不同约束：`credential_redaction.dart:28–40` 仅替换已知凭据或抑制 bearer/authorization 文本；`model_gateway.dart:767–776` 将其余异常文本写入账本 `error`。不能从“凭据测试通过”推导任意正文不会进入错误。`OutboundLedger.finish(:107–141)` 接受任意 `error`，故 caller 的错误来源仍需审查。

## 出口/级别矩阵

下表每行均包含生成成功、生成失败、embedding 成功、embedding 失败四种情况；没有把不存在的路径替换成 fake 路径。

| 出口 | INFO | DEBUG | 本次结果与界限 |
| --- | --- | --- | --- |
| 适配器显式 stdout/stderr logger | NOT_IMPLEMENTED | NOT_IMPLEMENTED | 对上述实际模型/knowledge 路径检索未发现 print/debugPrint/developer.log/stdout/stderr/Logger 或日志级别实现。不是进程级“捕获为零”的动态证明 |
| 适配器专用文本日志文件 | NOT_IMPLEMENTED | NOT_IMPLEMENTED | 未发现专用文件日志 sink；SQLite 外发账本单列如下，不把它当不存在 |
| SQLite 外发账本（实际文件持久化路径） | NOT_IMPLEMENTED（无分级） | NOT_IMPLEMENTED（无分级） | 路径存在；四种 canary 动态组合均 NOT_RUN。静态 schema 是摘要元数据；error 为开放文本 |
| 模型诊断日志导出 | NOT_IMPLEMENTED | NOT_IMPLEMENTED | 未发现模型诊断 export 入口；DataFlowSnapshot 是只读 UI 快照，不称其为导出 |
| Flutter/操作系统控制台、崩溃处理、系统日志 | NOT_RUN | NOT_RUN | 需实际运行与捕获；不能用适配器没有 logger 代替进程验证 |

工具链证据：`command -v dart`、`command -v flutter` 无结果；常见 `/opt/flutter`、`/opt/dart-sdk`、`/usr/lib/dart`、`/workspace/flutter` 不存在。Python 可用但不能执行实际 Dart 适配器，因此没有新建 `test_actual_log_paths.py`，没有编写 fake logger 后声称生产路径验证。后续授权增加了供 owner 运行的实际适配器 Dart fixture，详见下节；尚未编译/运行。没有下载工具链、权重、使用凭据或请求真实模型。

实际路径 canary 动态矩阵明确为 **24 格**（2 操作 × 2 结果 × 2 级别 × 3 出口）：

| 操作/结果 | stdout INFO | stdout DEBUG | file INFO | file DEBUG | export INFO | export DEBUG |
| --- | --- | --- | --- | --- | --- | --- |
| generation/success | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| generation/failure | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| embedding/success | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_IMPLEMENTED | NOT_IMPLEMENTED |
| embedding/failure | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN | NOT_IMPLEMENTED | NOT_IMPLEMENTED |

stdout 保守包含进程/框架控制台，因此 8 格 NOT_RUN；显式适配器 logger 的缺失已在上表标 NOT_IMPLEMENTED。file 包含实际 SQLite 账本，因此 8 格 NOT_RUN；账本本身没有 INFO/DEBUG 模式，不能伪造两种级别的通过记录。export 未找到模型诊断出口，因此 8 格 NOT_IMPLEMENTED。所有格均没有“0 泄漏”动态结论。

## 最小复现与补丁建议（交唯一集成 owner）

1. **生成/embedding 的语义失败可能已有 succeeded 账本（静态可达，动态 NOT_RUN）。** 在现有 `outbound_ledger_test.dart` 的实际 loopback fixture 中回复 HTTP 200 + `{"choices":[{"message":{"content":"   "}}]}`，调用 `gateway.chat`：`:346` 已 finish succeeded，`:233–234` 随后抛 Empty model response。embedding 回复 `{"data":[]}`，一个输入调用 `gateway.embed`：先 succeeded，再在 `:275–276` 抛 Invalid embedding response count。建议 owner 先决定账本状态表示传输成功还是完整操作成功；若表示操作结果，将语义校验置于统一完成点之前，或明确区分 transport 与 semantic outcome。`finish` 只更新 sending 行（`outbound_ledger.dart:126`），不能在事后简单再写 failed。新增断言应同时观察抛错、状态、无重复请求，不把合法业务 JSON `[]` 一律认作空响应。
2. **正文 error 边界需补运行证据，未确认产品泄漏。** 用实际网关 `clientFactory` 提供的受控 HttpClient，在响应 body stream 抛带合成正文 canary 的异常，检查账本/上抛错误/进程控制台；另用普通 HTTP 失败、畸形 JSON、provider error、有效生成与 embedding 分别放 canary。前者验证任意异常字符串穿过 `redactCredentials → ledger.error` 的边界，后者验证已有固定代码保护。若 owner 确认日志禁止任意正文，最小建议是网关将持久化的异常规范化为允许列表错误码；不要仅增加一个凭据正则表达式。
3. **共享旧 transport 限定。** `packages/supplier_core/lib/src/llm.dart:196–205` 对部分非 200 状态把前 300 字符正文附进 LlmException，这是潜在错误正文暴露，但没有 logger sink，不能报告为已观测日志泄漏。Muyon 当前 inquiry 通过 `apps/muyon/lib/app/inquiry_plugin.dart:440–458` 注入 `gateway.request` transport，绕开旧 `_http`；因此不能将旧 transport 的风险直接归为当前 Muyon 接线已复现。只在需要直接使用共享库旧 transport 时由 owner 独立评估。

## 新增真实适配器离线 fixture（NOT_RUN）

`experiments/redesign/memory-failure-validation-lab/actual_adapter_canary_test.dart` 直接 import 实际 `OpenAiModelGateway`、`OpenAiCompatProvider`、`OutboundLedger`、`StorageManager`、`WorkspaceRepository.schema`，不是 Python 模型或 fake 日志 sink。只绑定 `127.0.0.1` 临时端口；合成 canary 是普通正文，`_NoSecrets` 不提供任何凭据。复用现有 `outbound_ledger_test.dart` 的真实网关与 loopback 模式。

共 8 个普通测试：生成成功、embedding 成功、生成/embedding HTTP 500 失败、真实兼容 provider 的 SSE 成功/provider error、空白 chat/空 embedding 的语义账本契约各一条。前 6 个检查真实请求确实到达本机服务、无重复发送、实际 `print` zone 捕获、持久账本元数据、关闭后实际存储文件字节与重开后的账本；HTTP 失败还检查真实上抛异常没有 canary。预期业务结果中的正文可含 canary，检查目标是日志/账本，不是禁止业务输出。

最后 2 个断言失败后账本不可 `succeeded`，没有 skip/expectedFailure：固定基线源码推导会失败，尚未执行，不能报告“已复现 FAIL”。该契约也需要 owner 明确账本语义（见上节建议）。

此 fixture 的 ZoneSpecification 捕获 Dart `print`；**不能**拦截 `stdout.write`、stderr、native 日志、其他 isolate、Flutter engine、测试 runner 报告、崩溃日志，也不创造源码不存在的 INFO/DEBUG 配置或 export 入口。持久文件检查只覆盖 fixture 隔离 storage root。故即使将来这 6 个 canary 测试通过，也不等于完整 24 格或产品零泄漏。

owner 可在具备项目 Flutter SDK 和现有依赖的环境，从仓库根执行：

```bash
cd apps/muyon
test -f .dart_tool/package_config.json
flutter test --no-pub --reporter expanded ../../experiments/redesign/memory-failure-validation-lab/actual_adapter_canary_test.dart
```

命令依赖 `apps/muyon/.dart_tool/package_config.json` 的实际项目依赖解析；不调用 pub get、不下载 SDK。缺 SDK/package config 则仍为 NOT_RUN。不能直接用普通 `dart test` 替代 Flutter 测试环境。fixture 已对照现有测试/API 人工核查，但本机没有做 analyzer/formatter/编译；若有编译问题先仅修此实验文件，不能转而修改生产适配器。

新增价值是明确实际路径、现有断言边界、各出口 NOT_IMPLEMENTED/NOT_RUN、统一完成点的精确输入与可交付真实适配器断言；没有生产修复，也没有重做 current-member/revision/body-hash 防护。
