# REG-2b 交叉核实说明（给 Codex）

被审：`review/REG-2b` @ `e61a1db`（作者 `implementer-sonnet`，37 个文件，+4967/−367）· 任务说明 [REG-2b.md](REG-2b.md) · 依据 [ADR-0004](../adr/0004-module-contract-v2.md) §4～§6、§10.3 · 清单 [REVIEW.md](REVIEW.md)

只回报，不改 `review/REG-2b`；需要做变异或写探针时，在 `/tmp` 下用 `git archive` 导出的副本里做，结束后删除。跑测试前取消代理并设 `NO_PROXY=localhost,127.0.0.1,::1`，不要导出 `MUYON_EVAL_REAL`。原始日志不进仓库。

## 必查
1. **范围**：`git diff --stat origin/develop...origin/review/REG-2b`。确认没有碰 REG-2a 的文件（`outbound_ledger.dart`、`mcp_adapter.dart`、`inquiry_web_authority.dart`、`inquiry_hub_authority.dart`、`public_tools.dart`），没有迁移任何业务模块，没有残留 `apps/muyon/macos` 的改动。
2. **重跑**：
   - `flutter analyze`，覆盖 `muyon_module_api`、`apps/muyon` 等 7 个包；
   - `muyon_module_api` 全量测试，作者报 29 例；
   - 宿主全量 `flutter test`，作者报 813 例通过、3 例跳过；
   - `bash scripts/ci.sh`，作者没有整体运行过。本机 inquiry 的 golden 截图因 macOS 渲染漂移失败属已知情况，如实写明即可。
3. **已有测试**：
   - 唯一被改的是 `task_events_test.dart:99`（`== 8` 改成 `>= 8`）。判断它是否只是放宽版本断言、原意不变。
   - §10.3 清单里的测试一条都没改：用 `git diff` 确认。
4. **范围解析差分测试**：`support/legacy_scope_resolver.dart` 必须是旧 `resolveAssistantScope` 的原样副本，与 `origin/develop` 上的旧实现逐行对照。差分测试要覆盖科研、询价、知识库、原型，以及全局、工作区、选中这几种范围。
5. **注册器与授权**：
   - `HostToolRegistrar` 不暴露任何写回执、审批或 `outbound_*` 的接口；
   - v2 模块拿不到 `tools` 能力；`knowledge`、`models` 被拒绝（策略 `facade-pending`，见作者说明的偏离第 1 条），判断这样处理是否合理；
   - `module_grants` 的迁移 10 能正确建表。
6. **迁移占位**：作者放了一个空操作的迁移 9（`reserved-reg-2a-outbound-tool-requests`）。判断合入后 REG-2a 改用真实迁移 9 替换占位是否可行；如果开发库已经升到 10，REG-2a 的建表会不会被跳过。给出建议的合并做法。
7. **`tool_registry.dart` 新增的 `preflight` 钩子**：它在 `prepare` 里、签发审批之前调用。确认它不能放宽任何检查，只能拒绝。
8. **变异抽查**：自己挑三个做，不采信作者的结果。
   - (a) `supportedApiVersions` 加上 3；
   - (b) 把差分测试里旧实现的某个分支改掉；
   - (c) 让 `HostToolRegistrar` 暴露 `approve`。
9. **失败隔离**：一个模块激活失败时，其他模块仍然可用；工具注册阶段失败的模块一直保持失败状态，直到重启。判断这是否可以接受。

## 回报
核对表（满足 / 不满足 / 部分满足，附文件:行）、重跑摘要行、变异结果、发现（按 阻断 / 应改 / 可选 分级）、是否建议合入。
