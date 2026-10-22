# 一轮只读独立复审

结论：本轮曾独立复现 Finding2 的归属读取错误分类缺口，实现方随后修复；对冻结最终候选的原独立反例复验通过，65 项主套件通过。针对所给两项 finding，本轮未发现未解决的具体残余绕过或兼容性问题。旧 RED 及其源码证据保留如下。

## 范围与候选身份

- 仓库 `/workspace/mig20`，分支 `task/mig20-group-grant-tail-fix-20261022`。
- base `ecef00d8b296930bd40ad8f1ed06890fd7b8a7fc`。
- 只读审阅 production/test diff；没有修改生产或仓库测试文件，没有委派。
- 审阅时 `group_runtime/store.rs` SHA256：`2ced65d1e2baa5e3dc8b705ee6d186f836e5f1d7df900daf9f8346cdbbc1690d`。
- 审阅时 `tests/group_runtime_store.rs` SHA256：`4545917fdd56e529a9cf644ec576373336324aad473ce21bea305806287e1151`。
- 复现仅用新建 `/tmp` 合成 SQLite、现有真实 owner 实现和离线响应/dispatch fixture；没有 provider 网络、历史 unknown 或真实用户文件操作。

## 重建的不变量

1. effect/events/receipt/consume 属于同一 `BEGIN IMMEDIATE` 事务；提交前最后一次写入后的检查必须验证完整原 grant：grant id、generation、owner epoch、binding、local-only admission、原 expiry 且未过期；消费 UPDATE 必须恰好匹配一条原 active=1 行并写到 active=0，末态也需完整核验。
2. tail 所见 project 未删除、group workspace/project/current registration scope 和 revision 必须有效；group、event、intent receipt 必须匹配预期。末检后只读直至该事务 commit。
3. 返回 Rejected 必须有本事务成功持久化、scope/binding/status/receipt 匹配的 terminal intent；storage/commit/不确定 owner read 不能被当作业务拒绝；原 owner unknown 与 hold 不被修改。

## 已修复的独立发现：归属读取 Storage 被压成 NotFound 并永久拒绝

源码链路（本次候选行号）：

- `store.rs:623-625`：`group_lookup_original` 把 `owner.request_conversation` 的所有错误映射成 `ContractError::NotFound`。
- `store.rs:930-933`：Observe 调用该 lookup 后只经 `inconclusive_original_read`。
- `store.rs:1106-1111`：该 helper 仅将 Unknown 转为 Storage，故上面的 NotFound 原样流出。
- `store.rs:522-549`：execute 将 NotFound 进入非 Storage 分支，持久写入 rejected 并返回 Rejected。
- 同类遗漏还在 BindOriginal 的 `store.rs:907-909`；其 request_chain 已改为 Storage，但更早的 request_conversation 仍吞掉 storage 类型。
- 原 owner `owner.rs:748-749` 的 request_conversation 依赖真实 requests 表读取，因此 SQLite schema/read 故障确实走到上述分支，而不是输入不存在的确定业务结果。

独立复现：先创建并 bind 一个真实合成 unknown 原请求，保存 owner observation 与 hold；在另一个仅用于测试的 SQLite 连接将 `requests` 改名为 `synthetic_unavailable_requests`；执行有有效 grant/revision 的 Observe；恢复原表名，再验证原 unknown 与 hold 均与之前一致。

实际结果：

```text
receipt.status = Rejected
receipt.result.error = not_found
local intent durable status = rejected
local intent durable receipt.status = Rejected
original_unchanged = true
held_unchanged = true
assert expected PendingOriginal, got Rejected
```

这是原候选中的永久终态错误：恢复 owner 存储后，同 intent 会查询并重返该拒绝 receipt，而不能继续原本的不确定观察。原 unknown 未损坏，但本地 receipt 的确定性不成立。实现方已在同一轮内加入 `original_identity_read_error`，仅 `agent_request_not_found` 映射 NotFound、`agent_identity_invalid` 映射 InvalidIdentity，其余 owner 读取失败映射 Storage；Observe lookup 与 BindOriginal 均已使用。该修复只修改 group adapter，未改 owner 文件。

## 验证与原始证据

独立 `/tmp/mig20-tail-independent-review/review.rs` 使用候选测试文件的完整副本，将 source path 替换为仓库绝对路径并追加一条独立反例；没有改动仓库 tests。临时 Cargo manifest 使用相同依赖版本及原 lab 依赖。

公共环境：

```sh
PATH=/tmp/mig20-rust/bin:$PATH
CARGO_HOME=/tmp/mig20-cargo
CARGO_TARGET_DIR=/tmp/mig20-target
RUSTFLAGS='-L native=/tmp/mig20-native-libs'
```

1. 命令 `cargo test --offline --manifest-path /tmp/mig20-tail-independent-review/Cargo.toml --test review independent_owner_identity_storage_fault_must_remain_pending -- --nocapture`：exit **101**；**0 passed / 1 failed / 62 filtered out**。原始输出：[independent-identity-read.log](evidence/independent-identity-read.log)。
2. 命令 `cargo test --offline --manifest-path /tmp/mig20-tail-independent-review/Cargo.toml --test review -- --skip independent_owner_identity_storage_fault_must_remain_pending`：exit **0**；**62 passed / 0 failed / 1 filtered out**。原始输出：[independent-candidate-suite.log](evidence/independent-candidate-suite.log)。
3. 复现完整测试源：[independent-review-harness.rs](evidence/independent-review-harness.rs)；临时 manifest：[independent-review-Cargo.toml](evidence/independent-review-Cargo.toml)。

## Finding1 与 rejection 持久化路径评价

末端 consume 的 WHERE 已同时约束完整授权字段与原 expiry，返回 affected rows 必须为 1；随后核验 active=0 的完整原行及当前时间。events/committed receipt 触发器先发生，consume 触发器后仍有只读的完整 grant 和 project/group scope 检查，未见只检查 active=0 的旧问题。注册新 group 也走末端 scope/revision 检查。

rejected UPDATE 已约束 scope/binding/pending、检查 affected rows、读回精确 receipt 后 commit；任何失败返回 PendingOriginal。针对 ignore、篡改、SQL failure 的已有测试本轮通过。最终主套件还通过两项真实 deferred-FK COMMIT 故障测试，分别证明成功业务事务和 rejected 事务的 COMMIT 失败均返回 PendingOriginal 并回滚相应写入。本轮不声称穷尽全部 SQLite 故障或任意 SQL trigger 的业务数据完整性。

## 同轮最终候选复验

实现方通知生产候选冻结后，独立复验原 `/tmp` 反例，没有改变其断言或故障注入；没有另开审查轮次。

- 冻结 `store.rs` SHA256：`dde6c867c918402c60b083aedb21948fbfeddb848278705d6858c237c76ff034`。
- 冻结 `tests/group_runtime_store.rs` SHA256：`a3217b7bc9622f0a82a9a151ef74243015cbf42113ae9c87903d4e235cf8f5e0`。
- 原独立反例同命令重编译重跑：exit **0**；**1 passed / 0 failed / 62 filtered out**。真实结果为 `PendingOriginal`，持久 intent `[pending, NULL]`，原 owner observation 和 hold 未变。原始输出：[independent-identity-read-fixed.log](evidence/independent-identity-read-fixed.log)。
- 最终仓库主套件：`cargo test --offline --manifest-path crates/Cargo.toml -p muyon-core --test group_runtime_store`，同公共环境，exit **0**；**65 passed / 0 failed / 0 filtered out**。原始输出：[independent-final-suite.log](evidence/independent-final-suite.log)。
- 新增真实 COMMIT 故障覆盖为 `rejected_commit_failure_is_pending_without_committing_rejected_receipt` 和 `business_commit_failure_rolls_back_receipt_event_stop_and_grant`，均在上面的 65 项中通过。

## 阻塞与交付

无剩余已复现接受阻塞；没有工具审批阻塞、denied 或 uncertain 操作。本轮仅独立审阅、复现和记录，没有修改生产或仓库测试文件。
