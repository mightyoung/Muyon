# C6-REDO 模型披露不透明引用独立复审（CR-C6，ChatGPT）

对象 C6 `2ce7c96f`、组合 `bd719de7`（= develop `9de4235a` + C6）。云端静态只读，未运行测试或变异；CI 来自精确 SHA。原稿由用户转交，leader A 整理入库，代码位置以原稿为准。

**结论：需修改。** 无已确认 Critical；5 项 Important、1 项 Minor。HMAC 算法与 UI snapshot 字段门禁基本成立，但「所有生产出站路径均受保护」不成立。

| 编号 | 问题 | 位置 | 修改要求 |
|---|---|---|---|
| I-1 | 第二次摘要泄漏：首次摘要把完整引用存进 `conversationSummary.objectsAndReferences[*].reference`；再次摘要只投影 `messages` / `cleared`，`previousSummary` 原样进请求 | `agent_compaction_flow.dart:116-132,426-440`、`context_compactor.dart:389-418,448-473` | 投影完整的模型侧摘要请求（含 `previousSummary`），内部持久摘要可保留原引用；补「真实工具引用 → 摘要 → 继续 → 再摘要 → 查 HTTP body」负例 |
| I-2 | 字段白名单只覆盖 UI snapshot：`inquiry.object` 返回完整 `record.data`；global `inquiry.get/query/related` 返回 `legacyValue`；底层 `get` 遍历全部字段；工具结果历史放完整 `result.toJson()`；`projectModelJson` 只处理引用形态。另：manual 恢复历史拼成「摘要 + JSON」普通文本不被投影；Folio 模型桥经 `InquiryHostModels.createClient` 直接发 `preview.body`，不经 `AgentContext.view`（仍有逐次发送审批） | `business_tools.dart:108-198`、`supplier_core/agent_tools.dart:567-588`、`agent_dispatch.dart:864-887`、`model_reference_map.dart:129-176`、`agent_resume.dart:155-190`、`supplier_core/assistant.dart:363-392`、`inquiry_plugin.dart:436-471` | 把字段披露规则接到真实工具结果与桥接出站组成，本机保留完整结果；补 `inquiry.object`、global 查询、manual 恢复后聊天、Folio 第二轮 HTTP body 的自由文本正反例 |
| I-3 | 重启后句柄变化：pin 含内存 UUID 与 `identityHashCode(runtime)`，重启后同数据生成不同句柄；持久的待确认卡仍可被确认，`runModel` 用当前请求重建 review 却沿用旧 `requestDigest` → 确认内容与发送字节不一致 | `bootstrap.dart:134-141`、`workspace_repository.dart:24-32,258-261`、`personal_agent.dart:693-724`、`agent_model_turn.dart:382-420` | 重启或 binding 变化时旧卡失效并重新生成（或持久化经验证的完整 binding）；发送前核对当前投影与批准内容一致 |
| I-4 | `research.read_object` 的 `data.object.contentDigest` 是同一对象摘要的副本，逃过投影（既有生产者残余，ADR 已把非引用形态 `data` 排除在本轮外） | `research_module/module_tools.dart:169-186`、ADR-0004:736-742 | 收窄本轮验收声明并列遗留；后续由宿主把模型侧不透明前置条件还原为内部 CAS 摘要，不能直接删 `expected_digest` |
| I-5 | 生产路径只发行句柄，未见 `resolve` 的生产消费；`PersonalAgent.cancel` 不调 `revokeTask`；pin 只观察 Inquiry 与 Workspace authority；「authority moves」测试只改注入的 pin 字符串 | `model_reference_map.dart:97-117`、`personal_agent.dart:761-832`、`agent_dispatch.dart:144-168`、`model_reference_outbound_test.dart:293-327` | 明确 `modelRef` 是只供识别的输出标签还是可回传引用；可回传则补宿主解析、撤销关联与真实生命周期测试 |
| M-1 | 未知字段 canary：fixture 未能存入未知字段（CI 输出 `UNKNOWN_FIELD_STORED_BY_PUBLIC_STORE=false`）仍无条件断言通过 | `test/support/ui_disclosure_independent_helpers.dart:125-135`、`ui_disclosure_independent_test.dart:334-337` | 前置条件必须成立，否则标为未接通 |

已成立：HMAC-SHA256 绑定 task / scope / pin / 完整 ObjectRef；密钥 `Random.secure()` 32 字节（存普通 settings，非安全凭据库）；`notDisclosed` 残值强制 null；`sources.originalText` 不序列化；未登记 view/state/computed/draft 置空；内部 `contentDigest` 与 CAS 保留。改写的旧 canary 合理，未发现删减。
覆盖边界：`projectMessages` 只改写字符串 `content`（native `tool_calls.arguments`、带前缀的 JSON 未覆盖）；UI 规划请求末尾可能追加原始 answer；`research.qa` 有独立 `gateway.chat` 路径（专门证据审批契约）。四项变异本次未取得可核验执行记录。
