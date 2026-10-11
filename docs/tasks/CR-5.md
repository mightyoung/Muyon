# CR-5 首字延迟与卡片出现延迟的静态调研（ChatGPT 6 Pro，线上调研）

执行：ChatGPT 线上 · 只读 GitHub · 结果贴给用户，leader A 入库为 `docs/reviews/2026-10-11-latency-study.md`

## 背景
第二阶段退出标准要求首字延迟本机 `<1.5s`、远程 `<3s`（[HANDOVER-LEADER.md](https://github.com/mightyoung/Muyon/blob/develop/docs/tasks/HANDOVER-LEADER.md) 第 4 节）；卡片可见延迟还没有阈值。至今没有实测。Haiku 冒烟会测，但在那之前需要知道时间可能花在哪。

## 要做的事
1. 从用户点「发送」到首个文字增量显示，沿代码走一遍关键路径：`apps/muyon/lib/assistant/`（`personal_agent.dart`、`agent_model_turn.dart`、`agent_dispatch.dart`、上下文与压缩）、模型适配（`apps/muyon/lib/services/models/`）、授权与策略 gate、数据库写入。列出每一步：做了什么、是否同步阻塞、是否有磁盘或网络 I/O、在首字之前还是之后。
2. 同样走一遍「回答完成 → 规划 → 流式编译 → 卡片完整显示」（以 [PR42](https://github.com/mightyoung/Muyon/pull/42) 的接线为准）。
3. 找出最可能的瓶颈（推测要标「推测」），以及每一项的低风险优化思路；**不建议**动授权、确认、账本与事务顺序。
4. 设计测量方案：在哪些点打时间戳、如何避免把密钥或内容写进日志、需要几次取中位数；给 Haiku 冒烟和 E-1 评测共用。
5. 建议「卡片可见延迟」的目标阈值及理由，列为待用户决定。

只调研，不写实现代码；引用写 `文件:行`。
