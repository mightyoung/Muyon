# AIUI-1 执行说明与审查处置

执行任务分支 `task/aiui-1-streaming-compiler`。原基线 `49a03ec8bd62044e26431a257246f9da191fdd70`；用户更新要求后，保护本地实现并 `git pull --ff-only` 至 `71dd23a31bdcf0e07b0d4af5e48eb7c3df668696`。正式验收依据是 `docs/design/aiui-stream-contract.md`（aiui-stream/1）。未合并 develop/main，未改 catalog、UI-4b、模型、界面或 agent_dispatch。

## 字段表

| op | 必需字段 | 可选字段 | 映射 |
|---|---|---|---|
| text | md | — | 模型文字段落，独立于 UIPlan |
| node | id、component | 根不可带 parent；非根必须 parent；props、bind | UiNode；父先到，子按到达顺序追加 |
| patch | id、props | — | props 逐键合并；null 删除；不支持 bind/component/parent/children |
| action | node、event、action、inputs | operation（业务必需） | ActionBinding；actionRef=input.action，inputRefs=inputs，operationKeyRef=operation |
| end | — | — | 一次完整候选批量校验 |

所有操作含 op。bind 每项仅 `{kind,id}`，kind 为现有四种。宿主 UiStreamSession 给定 surfaceId/revision/root/snapshot/intent/catalog，生成 catalogVersion/snapshotRef/intentRef；流不能覆盖这些字段。业务 expectedDraftRevision 从宿主快照 actionContext.draftRevision 填入；本地/语义保持 null。目录定义 route，不接受模型 route 或 revision。computed 只引用快照已有结果，不新增公式注册表。uiState/sourceSpan 保留现有安全规则，不删既有能力。

## 规范解释

契约 §4 的两个要求无法在一个错误集合中同时成立：坏行不属于 UIPlan，validateUiPlan 不认识 malformed_stream。采用独立复核建议的分层解释：view.batchValidation 精确保留原始候选批量通过与否及错误序列；streamErrors 从诊断中过滤协议错误，属性校验诊断不算坏行；协议诊断独立累计，出现任何坏行就在 end 记录 malformed_stream 并拒绝流。只有批量合法且无坏行的流获得 view.finalPlan；拒绝 end 清空整个 UI 预览，但保留模型文字供宿主退路。没有把删除坏行后的候选合法冒称流合法。诊断保存共100条（包含节点与协议错误），超出后计数保留在 badLines/diagnosticCount 中。对应 `bad line veto is independent of exact candidate batch equivalence`。

契约 action 映射的修订字段按原 validator 收紧解释：只给 business 填 expectedDraftRevision；合法 local 输入为 uiState，operationKeyRef/revision 必须 null。对应 `business revision host filled; local refs remain null` 与 `missing action targets and local business refs are rejected`。

数量上限采用包含边界：≤N 允许，N+1 停止，因此恰好200节点之后 end 可以完成。诊断100条仅限制保存量，此后继续计数，不导致流终止。对应 `node limit permits N minus one and N, rejects N plus one` 与 `after end preserves first result; diagnostics truncate and keep counting`。UTF-8 字节计数；文字量累计 text 与收到的字符串 props（含替换属性），不计 JSON 语法或绑定id。UiStreamLimits.v1 集中定义全部默认值；测试可注入更小的限额。所有 v1 上限仅允许被配置为更严，不允许放宽；对应 `host limit configuration can only tighten v1 bounds`。

## 状态与规则抽取

validateUiNode 从原 validator 原样抽取组件、属性、绑定、事件及动作规则；validateUiPlan 保留整树/元信息/coverage 检查并调用该函数。未知组件仍不把绑定计入 shown，保持原错误集合。候选 UiNode 保留所有模式不合法的值；不可结构化的坏行不修改候选。独立状态表达 placeholder 或 blocked_by_parent；不伪造 catalog 组件或 ValidatedUiPlan。非法 patch 保留候选但预览使用最近合法版本，后续子节点和事件仍按现结构及动作规则校验；禁止子节点的父不能通过旧缓存继续显示。

阶段为 streaming/complete/rejected/incomplete/limitExceeded。完整 action 暂存候选，预览事件在完成前一律为空；中断和超限终态不可复活，后续行只计数。end 后的行忽略且有 after_end 诊断，第一结果稳定。text-only/空 end 按现批量空计划规则拒绝，文字保留。没有模型或界面退路接线，本层输出状态、文字与诊断供宿主处理。

## 契约对应测试

| 条款 | 测试名（ui_stream_test.dart） |
|---|---|
| §1 宿主元信息、协议版本 | session metadata and protocol version are host owned；forbidden metadata formula binding and v2 fields are typed bad lines |
| §2 解析及字段映射 | forbidden metadata formula binding and v2 fields are typed bad lines；business revision host filled; local refs remain null |
| §3 根/父/重复/无目标 | root ordering missing parent duplicates and missing patch are bad lines；parent without children support invalidates parent and blocks child；missing action targets and local business refs are rejected |
| §3 patch合并/null/保留候选回退 | invalid patch retains raw candidate and last valid preview；patch null deletes and key merge preserves other properties；invalid first version remains placeholder until valid patch；patch fallback survives new valid child but cannot hide forbidden children；valid action retains patch fallback but invalid action cannot use it；every JSON property stays raw and shared schema validation controls recovery |
| §3 action重复/缺字段 | duplicate events and missing business operation cannot finalize |
| §4 占位及父阻断 | node validation isolates placeholders and blocked descendants |
| §4 严格end和差分 | bad line veto is independent of exact candidate batch equivalence；batch coverage only applies at end and unknown component never satisfies it；各 binding/action 拒绝矩阵均比较原候选批量结果 |
| §5 绑定范围 | binding range rejects missing facts without rendering；missing stale and mismatched binding kinds match batch；action binding and allowlist rejection matrix matches batch |
| §6 中断和半截action | interrupted action remains disabled after complete action line；every truncated action line is inert and malformed |
| §6 终态和诊断 | after end preserves first result; diagnostics truncate and keep counting；pure text and empty end follow batch empty plan rejection |
| §6 八项上限 | node limit permits N minus one and N, rejects N plus one；depth boundary stops before accepting excess child；line byte boundary uses UTF8 and preserves prior preview；total text bytes includes text and all string properties；line bad line and per node patch quotas are inclusive |
| §8 v2不支持 | forbidden metadata formula binding and v2 fields are typed bad lines |

## 审查边界

初稿独立审查发现父链循环（阻断）和未知组件覆盖统计变化（应改），已修复并回归。正式 v1 结构约束更严：父必须先到且重复 id 拒绝，任何坏结构行不入候选，因此不能产生父链环。新旧 UI/AIUI 与 AIUI-F 路线命名有历史重叠，本任务不删除或擅改旧路线；由 leader 统一处理。第三方产品描述本轮未外核，不作私有实现事实。仅 ui_contract.dart 添加两个协议导出，其他实现集中 src/ui；原始验证日志留 /tmp，摘要写入提交说明。

正式v1复审发现合法child/action可抹去非法patch的lastGood，以及parser预筛schema属性类型导致不可恢复；已保留旧props并复核最新children/events，任意JSON属性保留原候选且只由共享schema校验判错，嵌套字符串以迭代扫描计入UTF-8文字量。对应最后两项恢复回归测试。

冻结终版独立审查通过：29项新增测试独立重跑通过，未发现剩余阻断。streamErrors过滤schema/after_end诊断不改变坏行否决；八项配置只能收紧。验证和四项真实变异摘要写入提交说明，原始日志未纳入仓库。
