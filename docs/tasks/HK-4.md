# HK-4 调度与模型回合的高风险特征测试（只加测试）

分支 `task/hk-4-dispatch-turn-characterization` · 基线 develop · 执行：Claude Haiku 5.5 · 审查：leader A

## 依据
[GB-4 特征测试清单](../reviews/2026-10-11-dispatch-turn-characterization.md)：`apps/muyon/lib/assistant/agent_dispatch.dart` 与 `agent_model_turn.dart` 没有直接测试，拆分前要先补。本任务只做**风险最高的前 5 个缺口**（第 3 节排序），对应第 4 节里的拟新增测试：
1. 迟到取消（lateCancel）之后不得再调用 `model.advance`；
2. `_recordResults` 提交失败时，已写的事件仍保留（按 GB-4 描述的实际预期为准）；
3. `_external` 路径；
4. 整卡预标记的并集；
5. `_correctableRead` 的两次读取。

## 要求
- 每个缺口照 GB-4 第 4 节对应条目写测试：测试名、构造步骤、断言、它要抓住的变异。**复用 GB-4 写出的现有夹具文件**，先读懂再照抄，不要从零搭。
- 每个测试写完后做它对应的那一次变异（GB-4 每条都写了「能抓住的变异」），确认测试失败，然后立刻恢复。5 次变异结果都写进回报。
- 读代码后发现 GB-4 某条的前提或预期和实际代码不符：**停下这一条**，在回报里写清实际行为和行号，其余条照做。不要为了让测试通过改断言去迎合疑似错误的行为——如果你认为实际行为本身有问题，单独列出来。
- 不改 `lib/`；新测试放进一个或两个新文件（如 `apps/muyon/test/hk4_dispatch_characterization_test.dart`、`hk4_model_turn_characterization_test.dart`）。
- `apps/muyon` 的 `flutter analyze`（0 个问题）与新测试文件；跑测试保留代理设置，`NO_PROXY` 加 `localhost,127.0.0.1,::1`；不导出 `MUYON_EVAL_REAL`；还原 `pub get` 生成的配置改动。

## 回报
提交哈希；每个缺口：测试名、结果、变异与是否检出；停下的条目及原因；`git diff --stat origin/develop`；analyze 最后一行。
