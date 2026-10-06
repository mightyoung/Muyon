# 统一调用路径审计（W2-A5）

日期：2026-10-04，基于 `develop@c6fdb74` + 分支 `feat/a-agent`。依据需求第五、七、九节：识别→筛选→提出→核对参数/范围/权限→确认→执行→核验→记录；用户界面与模型资料不能绕过；第三方接口记录权限、目的地与结果；取消如实说明已发生与未继续部分；结果不确定的外部操作先核实再重试。

方法：列出代码中所有工具执行入口与对外网络出口，逐一核对是否经过 `ToolRegistry`（prepare → approve → invoke → 回执）或等效闸门。证据类别：代码审查 + 自动测试；未做实机验证。

## 已符合

| 路径 | 闸门 | 证据 |
|---|---|---|
| `ToolRegistry` | 参数 schema、范围解析与执行前重解析、一次性宿主批准（会话绑定、限时、防重放）、结果引用范围校验、持久回执；中断返回 `interrupted` 不盲目重放 | `tool_registry_test` |
| 工具页手动运行（`platform_shell_knowledge.dart` runTool） | 同上，经 prepare/approve/invoke | 代码审查 |
| 个人助手工具调用（`personal_agent.dart`） | 模型只能提出冻结候选内的调用；批准由宿主 UI 发出，模型文本不能授权 | `personal_agent_test` |
| 模型请求（助手、科研问答、向量、询价） | 全部经 `OpenAiModelGateway.request`：显式端点、凭据引用、各调用方 `beforeSend` 确认 | `model_gateway_test`、`qa_scope_test`、`inquiry_shared_models_test` |

## 本次修复

1. **取消/失败按"是否已到达效应点"如实表述**（`tool_registry.dart`）。`checkBeforeEffect()` 通过即视为效应已开始：
   - 之前取消 → `cancelled`，明确"未执行任何写入或外部动作"；
   - 之后取消或出错（写/外部工具）→ `interrupted`，说明动作可能已发生、本地取消不撤销、重试前先核实；
   - 只读工具不产生不确定状态。
   测试：`tool_registry_test` 新增 4 项。
2. **出站记录 `outbound_requests`**（主库 v5，`platform/outbound_ledger.dart`）。每个模型请求在确认之后、发送之前写入：调用方、配置、端点与身份、位置、是否云代理、模型、载荷 SHA-256/字节数/条数；结束更新为 succeeded/failed/cancelled/timeout，并区分"发送前停止"与"已发送后停止"。记录写不进去则不发送。启动时遗留 `sending` 记为 `interrupted`（结果未知）。只存摘要与大小，不存载荷正文。测试：`outbound_ledger_test` 5 项（真实回环 HTTP）。

## 未符合（按负责人）

| # | 路径 | 问题 | 负责 | 建议 |
|---|---|---|---|---|
| G1 | `research_module/lib/src/core/lan_transfer.dart` + `app/lan_transfer_page.dart`（科研工作台可达） | 第三条独立局域网通道，明文、无设备认证，违反第十节 | C（领域）+ D（传输）+ B（页面） | D1 完成后改走宿主 `TransferService`；在此之前从宿主入口隐藏该页面 |
| G2 | `supplier_core/lib/src/assistant_web_tools.dart`（询价助手 ask 页可达，有用户审阅） | 对外网络不经工具注册表、不进出站记录 | C | 注册为宿主 `network` 效应工具（目的地 + 批准 + 回执），或至少写入出站记录 |
| G3 | `supplier_core/lib/src/hub.dart`（供应商中心发布可达） | 同上；属于第三方接口 | C | 同 G2；发布属外部写，失败或中断须先查询远端状态再重试 |
| G4 | `inquiry_module/.../app_state.dart:564` 独立 `LlmClient` | 宿主注入共享模型工厂时不应可达 | C（C1） | 加"宿主模式不可达"测试 |
| G5 | 询价模型请求调用方名 | 出站记录中调用方显示为默认 `model` | C | `inquiry_plugin.dart` 调用 `gateway.request(..., caller: 'inquiry')` |
| G6 | `services/ocr/ocr_models.dart` 模型下载 | 用户确认、固定 URL + SHA-256；不在出站记录中 | A（后续） | 低风险；出站记录扩展为通用网络请求时纳入 |
| G7 | `ManagedDatabase.raw` | 模块可绕过写队列直接写库 | A | 靠契约与审查约束；如需强制，后续以只读句柄替换 `raw` |

`supplier_core/lib/src/mcp_server.dart`：宿主与 inquiry 模块均未引用，宿主模式不可达，不列为问题。

## 未覆盖

- 科研问答 `QaService` 自带 prepare/approve 流程，未注册为工具；当前作为只读模型请求接受，已进入出站记录。若需要助手统一调用，后续注册为工具。
- 界面展示出站记录与工具回执（"数据去向"页）归 B。
