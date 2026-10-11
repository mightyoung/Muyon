# REG-3c-F → REG-3d 有界组合修复（待 root 独立复审）

分支 `task/reg3f-reg3d-integration-repair-20261011`。本交付不合入 develop/main，不改作者分支。根任务的唯一 integrator 另行决定合入。

## 来源与依赖

- 固定 F：`2aee00530b363f83398a788204626d11b3ab88b7`；完整保留 ancestry，包括 RED `89d870b4`、任务/CR13 所在 `5493220`、REG-3c-T 与 module-api 契约依赖。不只摘 F 顶层三个源码文件。
- 固定 D：`99bb4ff0279a4f94b3cf742404aec36de5a159cb`；与 F 分叉，共同基线 `9172e21639186f08e750341c323d85dcbef30f10`，D 不含 F。
- 组合 merge `da12cf3` 的第一父为固定 F、第二父为固定 D。冲突保留 F 的完整 outline 写入/typed evidence/同步 resolveCurrent 与 D 的 schema v10、领域期望 revision、绑定拒绝、七工具声明和读数据字段。
- 组合 RED：`884ebc2`。五个 D 写工具原行为临时作为 legacy helper 保留，确定性交错测试得到 0 pass / 10 fail 后才改为事务内冻结。
- 读取最新 develop `5225064` 的当前状态、HANDOVER、REVIEW，以及 REG-3c-F、CR13、REG-3d、GB-2 和 GB-3。仓库与相关祖先未发现 AGENTS.md。按 systematic-debugging / test-driven-development 工作流调查与先 RED 后修；本修复不是独立非作者复审。

## F 原 CI 失败与固定基线对照

[38134010631](https://github.com/mightyoung/Muyon/actions/runs/38134010631) 精确 checkout F，终态 completed/failure。8 analyze 通过；research 220 pass；host 1701 pass / 3 skip；唯一失败为 supplier_core 497 pass / 4 skip / 1 fail：

`test/lan_security_test.dart:310`，`absolute deadline ends a trickling upload and removes partial data`，Expected 200 / Actual 400。诊断表明第一次 trickle 在 read 阶段 150431us 到绝对截止；第二次短上传进入 flush 后，在 151214us 到截止，随后 validateLength 记录 format，响应 400。生产代码明确在 flush/close 后检查 `timedOut`，到截止会拒绝；不能把这项失败说成科研逻辑失败。

本次 Flutter 3.47.5 / Dart 3.13.4 云环境实跑：固定 F 最小用例 4 次均通过；共同基线 9172e216 对照 1 次通过；两树 supplier_core 源码和该测试 diff 为零。固定 F supplier_core 全量 498 pass / 4 skip / 0 fail。因此本机未复现原 CI 的 deadline/flush 时间窗口，不能声称已彻底修复供应包问题；无改 timeout、删断言或供应包补丁。原失败记录保留为复审注意项。

## 科研修复与合同核对

| 项目 | 结果与依据 |
|---|---|
| F typed evidence | 同事务、checkBeforeEffect 前按引用类型验证；同项目跨类型同号拒绝；未接受 run 拒绝。完整 F tests 保留。outline 仍只存裸 ID，带类型存储未做。 |
| F 冻结回执 | 同事务生成 changes/ref/digest；事务外不查最新行；原 A/B 更新和删除用例保留。 |
| F 边界移动 | 首/末/单段无变化 summary 保留，changes 和日志为空。 |
| D project/note | 五写工具之一的 update_project/set_note_entry 使用 F 同步 _report，在 _outlineWrite 事务中冻结；期望 digest、范围和 approval 守卫保留。 |
| D create/revise task | _taskWrite 同样返回事务内 ToolCallResult；新建 A revision=1、修订 A revision=2 不被 B revision=2/3 替换；expectedRevision 与字段白名单保留。 |
| D confirm binding | 拒绝不存在/已确认目标与 binding digest 校验保留；回执 document 引用在同事务冻结。绑定没有独立 ObjectType；文档 digest 表示文件内容，不冒充绑定行 digest。 |
| D migration / logging | schema v10 project/note 触发器与旧行种子保留，saveTask expectedRevision、applyBindingChoice 拒绝补丁保留。 |
| D reads / deferred | list_notes/list_bindings 与 read_object digest/revision 字段保留；binding.insert、manual run、export 仍未开放。 |
| 授权 / 防重放 | 沿用原 prepare / 一次 approval / invoke / receipt 链，不改宿主授权、回执身份、防重放或取消处理。 |

新增 `apps/muyon/test/reg3d_receipt_snapshot_test.dart` 复用 F 的 `_AfterCommitDatabase`：实际 A 提交后、其 write Future 返回前，使用原 runtime 插入实际 B 事务（更新或删除）。五工具 × 两种交错，断言提交后的 A 状态、B 确实执行、A succeeded 的持久回执、返回 refs/changes 精确等于 A 快照；任务断言自己的 revision，文档更新改变实际临时文件 digest。删除尊重外键、清理子行；没有 sleep、修改生产调度或伪造结果。

## 本次验证快照

原始日志仅保留云工作区 /tmp，未入仓库。pub get 自动改动的非交付 analysis_options 已还原；只格式化改动文件。使用官方 Flutter 3.47.5 Git tag/engine SDK 安装于 /workspace；缓存与 analyzer state 使用 /workspace 下目录，无权限扩大、凭证配置或真实模型/设备运行。测试保留代理，NO_PROXY/no_proxy 加 localhost；未导出 MUYON_EVAL_REAL。

- 固定 F：research strict analyze 无问题；host strict analyze 无问题；research 全量 220 pass / 0 skip / 0 fail；host 全量 1701 pass / 3 skip / 0 fail；typed evidence + snapshot 专项 14 pass。
- 组合：两包 strict analyze 无问题；research 全量 231 pass / 0 skip / 0 fail；F 专项 + D 原契约 + 新交错专项 48 pass / 0 fail。组合 host 全量与精确最终远端 SHA 的 CI 终态由交付回报/草稿 PR 补充，不能用 F/D 源 CI 代替。
- D 恢复事务外 resolve 的 mutation：0 pass / 10 fail；所有五工具 update/delete 均检出。
- F 恢复跨表裸 ID 查找：3 pass / 2 fail（已接受和未接受同号 run 均检出）。
- F 恢复事务外回执查询：0 pass / 2 fail；恢复边界旧摘要：0 pass / 4 fail。
- 额外 D 变异：移除期望值核对 19 pass / 5 fail；以未选定 entry 构造引用替代范围核对 2 pass / 2 fail；移除 v10 project/note 触发器 0 pass / 2 fail。都检出对应合同拒绝/日志行为，全部恢复。

## 范围与剩余边界

本组合保留原 F/D 的交付差异与测试；新增修复只涉及 research module 的五 handler/_taskWrite、合并遗漏的 D read_object 数据字段，以及 lint 花括号。没有改供应包、CI 门禁、既有测试断言、平台文件或凭证。源测试中的 schema 9→10 与 migration 索引变更来自固定 D。

CR13 N-2/N-3（删除确认显示级联对象、持久回执 ChangeOp 版本化）、outline 带类型证据身份、真实模型/真机与最新 develop 的最终 integrator 组合均未由本次完成。核心事务改动须交 root 非作者独立复审；CI 成功也不替代该复审。
