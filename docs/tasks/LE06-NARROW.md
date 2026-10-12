# LE06-NARROW：把预约路径的错误归类收窄到 SQLite 锁错误

执行：grokbot（路线 1，**先于 E01**）。派发：leader A，2026-10-12。集成：leader A。基线：develop `9de4235a`（已含 LE06-RACE 修复）；分支 `task/le06-narrow-busy-20261012`。

## 问题（复审结论，leader A 与用户转达的核读一致）
`9de4235a` 在 `apps/muyon/lib/platform/local_export_ledger.dart` 约 364-440 行把预约路径上**所有** `ledger_read_failed` 都改报为 `ledger_pending_failed`，并把 `_existing(...)` 也包进同一 try。归类范围比「对端持有写锁导致 SQLITE_BUSY / SQLITE_LOCKED」更宽：
- 账本行损坏、schema 不符、JSON 解析失败等真正的读取失败，也会被报成 pending 竞争；
- 已存在回执的读取（`_existing`）中出现的读取失败，同样被改写。
pending 先落盘、unknown 不自动重试两条约束保持不变（复审确认）。

## 要做
1. 先写会失败的测试：
   - 预约前读取遇到 SQLITE_BUSY / SQLITE_LOCKED → `ledger_pending_failed`（现行为，保持）；
   - 账本行损坏 / 不可解析（非锁错误）→ 仍报 `ledger_read_failed`，零执行；
   - 已有回执在 `_existing` 读取时损坏 → `ledger_read_failed`（或既有更具体错误），不得变成 `ledger_pending_failed`。
2. 实现：只在底层错误确属 SQLite busy / locked（按 sqlite3 扩展结果码判断，不靠消息字符串）时映射为 `ledger_pending_failed`；其余原样抛出。`_find` 包装需保留可判别的原因。
3. 双进程竞争测试 `two independently gated processes contend for one pending reservation` 断言不动；本机或获准环境在负载下重复 ≥30 次全过。

## 变异（必须做）
恢复成「所有 ledger_read_failed 都映射」；把损坏行判成 busy。测试必须失败。

## 回报（固定 6 行）
1. RED 与失败首行　2. 修复提交（远端与本地一致）　3. 改动文件与行数　4. 变异结果；竞争测试重复次数与结果　5. analyze 与 `apps/muyon` 全量（pass/skip/fail 及分类）、精确 SHA CI　6. 未做或有疑问

## 追加（2026-10-12）：子进程构建与共享 native assets
CF-FIX-B 精确 SHA 的 CI（run 38258595733）里，`assistant_transfer_capability_boundary_test` 因 `Couldn't resolve native function 'sqlite3_initialize'` 失败，同一日志中 LE06 竞争测试正在启动子进程（测试注释已指出「并发构建会共享生成的 dylib」）。请一并核查：LE06 的子进程是否会重建或覆盖 `build/native_assets` 下的共享库，从而让同一 CI 进程里并行的其他测试偶发加载失败；若是，让子进程使用隔离的构建目录或预构建产物（不得删除或跳过该竞争测试）。在回报第 6 行写结论与证据。
