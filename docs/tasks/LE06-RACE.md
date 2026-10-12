# LE06-RACE：组合 CI 阻断——双进程竞争同一 pending 预约的断言失败

执行：Codex（路线 1）。派发：leader A，2026-10-12。基线：UI 与存储组合 `review/ui-storage-current-combo-20261012` @ `326ca1387f01d7a620297e3525150f156659be3c`；分支 `task/le06-race-diagnosis-20261012`（本分支 = 该组合 + 本说明）。

## 事实
- CI 38210369162（326ca138）failure：host 2290 通过 / 3 跳过 / 1 失败，失败为 `apps/muyon/test/le06_recovery_independent_test.dart` 第 373 行附近 `two independently gated processes contend for one pending reservation`：`Expected: true / Actual: false`，即失败进程既不是 `state == 'unknown'`，也不是 `error == 'ledger_pending_failed'`。日志里没有 loser 的实际 state / error。
- 同一组合去掉最后 4 个 N2 无障碍提交的 `d5873ef4` CI **成功**；这 4 个提交（`7a4ba99d`、`dc7f2e97`、`4956803e`、`326ca138`）只改 research 预览，与 LE06 无直接关系。这提示是时序相关的不稳定，但**未证实**，不能据此定性为环境噪声。
- develop `ab5506c3` 已含该测试且 CI 成功。

## 要做
1. **先取证，不改断言**：在测试里把 `results`（两个子进程的完整结果 JSON）在断言前打印到测试输出（或断言 `reason:` 带上），推一次提交跑 CI；本机也在负载下重复运行该测试 ≥20 次，记录每次 loser 的 state / error 分布。
2. 根据实际 loser 值判断根因：是 SQLite 锁竞争返回了第三种合法终态（例如 `failed` + 某个锁错误码）、子进程启动或 go 文件的时序漏洞，还是实现真的在竞争时走了错误分支（例如自动重试、或把锁错误误报成别的状态）。
3. 修复按根因走：
   - 实现缺陷 → 修实现，断言不变；
   - 测试时序漏洞 → 只修门闩 / 同步，断言不变；
   - 锁竞争的合法终态确实不止两种 → **停下回报**实际值与理由，由 leader A 决定是否改断言（不得自行放宽）。
   pending 必须先落盘、unknown 不得自动重试，这两条不能动。
4. 修后：本机重复 ≥30 次全过；推送后该分支精确 SHA 的 CI 成功。

## 约束
不删、不跳过、不放宽该测试或其他断言；不改 main、不合 develop、不强推；不提交 pub get 改的平台文件。

## 回报（固定 6 行）
1. 取证提交哈希与 CI 链接；loser 实际 state / error 分布（本机 N 次 + CI）
2. 根因（一句）与证据
3. 修复提交哈希（远端与本地一致）、改动文件与行数、属实现还是测试同步
4. 修后本机重复次数与结果；精确 SHA 的 CI 结果
5. analyze 与 `apps/muyon` 全量（pass/skip/fail 及分类）
6. 未做或有疑问
