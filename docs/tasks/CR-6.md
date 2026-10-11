# CR-6 原子批量写入的执行契约设计（ChatGPT 6 Pro，线上设计）

执行：ChatGPT 线上 · 只读 GitHub · 结果贴给用户，leader A 入库为 `docs/design/atomic-batch-write-contract-2026-10-11.md`

## 背景
用户已决定（ADR-0001 末尾 2026-10-11 条）：批量写卡为**同模块、同类型、同操作、同范围的原子提交**，上限先定 50 条；外部内容任务只给逐项决定。现执行链逐条审批、逐条写入、失败即停，不具备整批回滚（`apps/muyon/lib/assistant/agent_dispatch.dart`）。设计依据：[本体写卡设计](https://github.com/mightyoung/Muyon/blob/develop/docs/design/ontology-write-cards-2026-10-11.md) 第 1.5、5.4～5.6、8 节，[ADR-0002](https://github.com/mightyoung/Muyon/blob/develop/docs/adr/0002-graded-assistant-authorization.md)，通用写工具 `apps/muyon/lib/platform/inquiry_record_tools.dart`（`reg4c` 业务回执、`operation_id`、`expected_version`），`Store.transaction`（`packages/supplier_core/lib/src/store.dart`）。

## 要设计
1. 复合工具的形态：工具 ID、参数（批次 `operation_id`、稳定行标识、每行目标 / 预期版本 / 变更）、结果（整批回执与逐行结果）；与现四个通用工具的关系（复用其单行校验与写入函数，不复制逻辑）。
2. 授权：一次审批绑定整批精确摘要；摘要怎么算；批内任一行变化如何使批准失效；外部内容任务如何退化为逐项。
3. 执行：同一领域事务内全部前置检查 + 写入 + 整批业务回执；任一失败全部回滚；取消与超时语义；幂等（同批次 ID 重放、换内容拒绝）。
4. 恢复：回执未知时如何查核整批是否已提交；不得换 ID 重发。
5. 宿主与模块边界：哪些在宿主（审批、摘要、范围、污染），哪些在插件（领域校验与事务）；需要 `muyon_module_api` 增加什么（与 GB-5 的「类型 × 操作」声明衔接，如有冲突写出来）。
6. 上限与预算：50 条之外，参数字节、事务时长、确认卡展示的约束。
7. 验收：拒绝路径清单（例：任一行版本不符整批不写、无部分成功回执；重复对象拒绝；换内容同 ID 拒绝；外部内容不出整批放行）。
8. 待用户决定的问题与推荐。
只设计，不写实现代码；引用写 `文件:行`。
