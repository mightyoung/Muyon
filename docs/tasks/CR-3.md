# CR-3 冒烟集成测试 aiui_smoke_test.dart 的规格（ChatGPT 6 Pro，线上设计）

执行：ChatGPT 线上 · 只读 GitHub · 结果贴给用户，leader A 入库为 `docs/design/aiui-smoke-test-spec-2026-10-11.md`，再派实现

## 背景
默认开启前要由 Claude Haiku 在 Android 真机上跑冒烟（[操作说明](https://github.com/mightyoung/Muyon/blob/develop/docs/tasks/AIUI-SMOKE-ANDROID.md)，验收项 1～7）。原定由 Codex 写的集成测试 `apps/muyon/integration_test/aiui_smoke_test.dart` 因 Codex 额度用完无人写。模型配置走 `--dart-define`（写法见 [North Star 运行手册](https://github.com/mightyoung/Muyon/blob/develop/docs/implementation/north-star-inquiry-runbook.md) 第 79 行起与 `apps/muyon/integration_test/support/north_star_settings.dart`）。生产接线见 [PR42](https://github.com/mightyoung/Muyon/pull/42) 与 [CR-1 审查](https://github.com/mightyoung/Muyon/blob/review/gb-1-invariant-audit/docs/reviews/2026-10-11-pr42-design-review.md)。默认开启计划：[https://github.com/mightyoung/Muyon/blob/develop/docs/tasks/AIUI-DEFAULT-ENABLE-PLAN.md](https://github.com/mightyoung/Muyon/blob/develop/docs/tasks/AIUI-DEFAULT-ENABLE-PLAN.md)。

## 要产出的规格
1. 测试文件结构：复用哪些现有夹具（North Star 链路的种子、模型设置、证据输出），新增哪些。
2. 逐条对应操作说明验收项 1～4 与 7：每条的步骤、断言（只能断言宿主可观察的状态：已保存卡片、回执、执行记录、界面元素）、真实模型下的非确定性如何处理（例如断言结构而不是文字）。
3. 延迟测量：首字延迟与「提交到首张卡片完整布局可见」怎么在集成测试里打点，至少 5 次，输出原始值与中位数到证据 JSON；证据里不得有密钥、端点、本机路径。
4. 离线与失败：无模型、断网、取消、超时各怎么构造，期望看到什么（对照流式契约的退路；注意 CR-1 指出退路尚未实现，SN-3 在补）。
5. 前置依赖清单：哪些能力目前还没合入（PR42、SN-3、三档、卡片接线），测试应如何在缺失时**明确失败**而不是跳过。
6. 风险与待用户决定的点。

只写规格，不写实现代码；引用写 `文件:行`。
