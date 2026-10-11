# REG-3c-T：补 REG-3c 写入守卫的测试（合入后复核发现）

执行：Codex。派发：leader A，2026-10-11。基线：develop `e7af6ab`（REG-3c 经 PR #44 已合入）。

## 发现
leader A 在 `/tmp` 副本对 `packages/research_module/lib/src/module_tools.dart` 的 `_outlineWrite` 做变异，跑 `apps/muyon/test/reg3c_outline_tools_test.dart`（17 例）和 research_module 全包（220 例）：
| 变异 | 结果 |
|---|---|
| M1 `_requireExpected` 恒通过（跳过「用户看到的状态」核对） | 被抓 |
| M2 删掉 `refs.any((ref) => ref.nativeProjectId != projectId)` 跨项目拒绝 | **两处都存活** |
| M3 删掉 `apply` 前的 `ctx.call.checkBeforeEffect()` | **两处都存活** |
| M4 删掉事务内 `runtime.requireCurrent(ref)` | REG-3c 测试存活；全包结果未出 |

## 要做（只加测试，不改源码）
1. M2：一次调用带两个不同 `nativeProjectId` 的对象（如 move/cite 涉及两段）→ 断言 `Object outside scope`、零写入。
2. M3：让 `checkBeforeEffect` 抛出（撤权或取消在事务内生效）→ 断言零写入、无回执、无变更日志。
3. M4：确认后、写入前把目标对象删除或改为非当前 → 断言拒绝、零写入。
4. 每个测试先在源码打对应变异确认失败，再恢复；回报失败第一行。
5. 若某条在当前架构下不可达（例如 resolvedScope 已保证单项目），停下写明证据，不要硬造测试。

## 约束
只在 `task/reg-3c-guard-tests` 提交推送；不改生产代码；strict analyze 零 info；不提交 pub get 改动的平台文件。

## 回报（固定 5 行）
1. 提交哈希（远端与本地一致）
2. 新增测试名
3. M2/M3/M4 各自打变异后的失败第一行（或不可达证据）
4. analyze 与 research_module、reg3c 测试结果
5. 未做或有疑问的地方
