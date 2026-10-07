# AUTH-1a 审查

审查分支 `review/AUTH-1a` @ `19230ee`（Codex）· 审查：leader 自审（读核心代码、在 `/tmp` 副本里跑测试和变异；按额度约束不派子代理）· 2026-10-07

## 范围
7 个新文件：`platform/grants/` 下的 `grant.dart`、`grant_resolver.dart`、`grant_store.dart`、`outbound_content_reviewer.dart`、`grants.dart`，加上 `app/host_ui_grant_authority.dart` 和测试 `assistant_grants_test.dart`。没有改任何已有文件，也没有接线。

## 核对
| 项 | 结论 |
|---|---|
| 解析规则 | 满足（`grant.dart` 的 `matches`）：类别、工具、范围、目的地必须全部一致；撤销、过期、次数用完都不命中；`task`、`conversation` 分别按 `taskId`、`conversationId` 限定；任务被外部内容污染后，`write` 和 `outbound` 不命中，`model` 仍可以命中；外传不能是 `always`，必须有目的地，`once` 以外的外传必须绑定对话（ADR-0002 §5 Q2）；只读类直接报错 |
| 第二道防线 | `assistant_grants` 表的 CHECK 约束重复了上述外传规则和时长规则，即使绕过 Dart 层直接写库，也存不进违规的授权 |
| 来自宿主界面 | `HostUiGrantToken` 的构造器是私有的，只有 `withConfirmedHostUiGrant` 能签发，回调结束后令牌就失效（`checkActive`）。`grants.dart` 只导出令牌类型，不导出签发函数 |
| 审查器 | `ReviewerChain` 取最严的结果；审查器抛异常或超时都按 `confirm(「内容审查未完成，需要人工确认」)` 处理，并标为「未审查」；超时时长必须为正 |
| 迁移 | **偏离，可接受**：迁移 11 写成了 `GrantStore.migration`，但没有登记进宿主 schema，原因写在注释里（迁移 9、10 属于 REG-2a、REG-2b，要先合入）。登记放到 AUTH-1b 接线时做 |
| 运行 | `flutter analyze` 没有问题；`assistant_grants_test` `+19: All tests passed!` |

## 变异（leader 亲自做，全部被抓住）
- 去掉范围比对 → `all three bindings and category must exactly match` 失败。
- 去掉外部内容污染判断 → `tainted tasks never match write or outbound but may match model` 失败。
- 审查器异常时改成放行 → `reviewer timeout requires confirmation and cannot weaken a block` 失败。

## 留给 AUTH-1b
- 把迁移 11 登记进宿主 schema（排在 REG-2a 的 9、REG-2b 的 10 之后）。
- `GrantResolver.resolve` 不消耗次数；接线时，签发审批前要用同一个请求调用 `recordUse`，次数的重新校验与递增在同一个事务里完成（`grant_store.dart` 已经这样实现）。
- 再加一个测试，扫描 `assistant/` 目录，确认没有引用 `host_ui_grant_authority.dart`。任务说明要求过这一项，本次只用私有构造器做了保证。

## 结论
**合入**（等 CI 跑完）。
