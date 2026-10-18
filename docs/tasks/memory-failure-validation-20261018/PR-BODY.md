补充记忆替换失败、空模型结果与正文日志边界的隔离证据：21 项 Python 合同测试覆盖 SQL 插入中途失败、SQL 成功而向量失败、进程退出恢复、删除后迟到修复及空正文/合法 `[]` 区分。另交付 8 项调用实际 Muyon gateway/provider 的离线 Dart fixture，当前环境缺 Dart/Flutter，均未编译、未运行；日志矩阵明确 NOT_RUN / NOT_IMPLEMENTED，无生产零泄漏声明。

- 基底固定为 B06 handoff `6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa`，PR 目标为 `docs/leaderb-next-20261018`，避免把既有候选混入本次 diff。
- 只新增 `experiments/redesign/memory-failure-validation-lab/**` 与 `docs/tasks/memory-failure-validation-20261018/**`。无 UI/host/AIDL/Gradle/模型适配器/现有 Hy crate 改动。
- 对照两个 Hy 候选全部实验 blob 相同，列出既有 24 个测试 ID；本机缺 Cargo，旧测试 NOT_RUN，没有重修 current-member/revision/body-hash。
- 独立固定源码复审 `0090b6e394abcbd8556a0911f4d5be1ff18687f5`：21/21 Python PASS，无阻塞发现。后续仅补证据/说明，不改测试实现。
- 静态发现 gateway 请求传输成功先于 chat/embed 语义校验的账本完成点歧义，附最小复现与补丁建议，交唯一集成 owner 决定；不在此修改生产。

Validation: `PYTHONDONTWRITEBYTECODE=1 python3 experiments/redesign/memory-failure-validation-lab/run_suite.py`；21 tests / 0 failures / 0 errors / 0 skips。真实 Dart canary、既有 Rust/Dart suites、设备与前后端联调均未运行。本实验不证明产品实现或模型收益。

I04 旧 script 状态→HTTP 操作保持 DENIED_BEFORE_EXECUTION，未执行/重试/改写/拆分/换执行者。Draft only；不合入 main/develop、不强推、不部署。交接见 `docs/tasks/memory-failure-validation-20261018/HANDOFF.md`。
