# CR-C6：C6-REDO 模型披露不透明引用独立复审（ChatGPT）

派发：leader A，2026-10-12。只读审查。
对象：Sonnet 的 `task/c6-opaque-reference-redo-20261012` @ `2ce7c96f`（16 文件 +2261/-43，含 ADR-0004 补充）；组合 `review/leader-a-batch-20261012a` @ `bd719de7`（= develop `9de4235a` + C6）。任务说明 `docs/tasks/C6-REDO.md`（在 C6 分支）。参考旧候选 `e6579861`（失败，未合入）、PR #65 canary `82c2c20d`。

## 重点
1. 不透明引用：宿主持久密钥对 task、scope、pin 与整行摘要做 HMAC。是否真绑定 task / scope / snapshot；伪造、跨任务、过期、撤销是否都拒绝；密钥持久化（`bootstrap`）是否安全；「重启后旧句柄不能解析、重新投影得到同样句柄」是否自洽。
2. 统一投影 `agent_context` 是否覆盖所有发往模型的消息：真实 prompt 组装、系统提示范围、工具结果历史、确认卡与实际字节一致、`agent_resume`、`ui_planning`、`agent_compaction_flow`（**摘要请求只做了投影代码，无端到端用例**）、global bridge、授权卡。列出任何绕过路径。
3. 自由文本 `notes` / `award_note` / `requirement` 默认不出站；未知字段遮盖；契约层 `notDisclosed` 残值、`sources.originalText`、`currentView`、`initialState` 走统一门禁。
4. 改写的旧测试（`ui_disclosure_independent_test` 的 C6 一例）是否合理；测试有无删减放宽。
5. 范围外项：工具结果 `data` 里科研 `expected_digest` 等非对象引用键未动——是否构成泄漏。

## 回报
Critical / Important / Minor，每条给文件:行与失败场景；最后一行结论：可合入 / 需修改 / 不可合入。
