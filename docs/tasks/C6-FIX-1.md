# C6-FIX-1：摘要二次泄漏、重启后确认字节不一致、modelRef 契约（CR-C6 I-1、I-3、I-5、M-1）

执行：Sonnet（**做完 CF-FIX-B 后接**）。派发：leader A，2026-10-12。集成：leader A。基线：你的 C6 `2ce7c96f`（之后 rebase 到合入时的 develop）；分支 `task/c6-fix-1-20261012`。依据：`docs/reviews/2026-10-12-c6-opaque-reference-review.md`（在 `task/docs-20261012a`）。I-2 字段披露另派 C6-FIX-2，I-4 作为遗留单列，本任务不做。

## leader A 定的契约（I-5）
`modelRef` 本轮定为**只供模型识别的输出标签，不接受模型回传**：工具参数里出现 `mr1_` 句柄一律拒绝或忽略（按工具现有定位字段与 scope / 权限检查执行），文档与 ADR-0004 补充小节写明；因此本轮不做宿主解析入口。`PersonalAgent.cancel` 仍要调用 `revokeTask`，保证取消后同任务不再发行。删除或改写只直接调用 `map.resolve` 的测试声明，不得再宣称「生产伪造 / 跨任务 / 过期 / 撤销路径已验收」。

## 要做
1. **I-1**：投影完整的模型侧摘要请求，包括 `referenceData.previousSummary`；内部持久摘要保留原引用。测试：真实工具读回带 `contentDigest` 的对象 → 第一次摘要 → 继续产生历史 → 第二次摘要 → 断言实际 HTTP body 不含该摘要。
2. **I-3**：重启或 binding（pin）变化后，持久的待确认模型请求卡必须失效并重新生成；发送前比较「当前投影的请求字节摘要」与「卡上批准的 requestDigest」，不一致拒绝发送。测试：卡停在 waitingConfirmation → 模拟重启（新宿主实例、相同数据与 HMAC 密钥）→ 确认旧卡 → 不发送、要求重新确认。
3. **I-5**：按上述契约实现与文档化；模型回传句柄的负例测试。
4. **M-1**：未知字段 canary 的前置条件必须成立（能存进未知字段），否则测试明确失败或标为「未接通」，不得无条件通过。

## 变异（必须做）
previousSummary 不投影；发送前不比较投影摘要；cancel 不调 revokeTask；canary 前置条件不检查。都必须被测试抓到。补交上一轮四项变异的可核验记录（命令与失败首行）。

## 回报（固定 6 行）
1. RED 与失败首行　2. 修复提交（远端与本地一致）　3. 改动文件与行数　4. 变异结果（含补交的上一轮四项）　5. analyze 与 `apps/muyon`、`muyon_module_api` 全量（pass/skip/fail 及分类）　6. 未做或有疑问
