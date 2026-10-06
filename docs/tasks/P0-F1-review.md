# P0-F1 审查

审查分支 `review/P0-F1` @ `8de0ca3`（与 `task/p0-f1-lan-flaky-test` 相同）· 审查 leader（接任）· 核实子代理 Opus · 2026-10-06

**结论：通过，合入。** 无阻断、无应改。

## 范围
只改 `packages/supplier_core/test/lan_security_test.dart`（+22/−1），不改产品代码。没有 sleep、加长超时、重试，没有放宽断言或 ECONNRESET 白名单（`{54,104,10054}`）。新增的 `expectUploadPending`（test:116-128）轮询一个确定事件（收件箱出现 `push-` 暂存目录），2 秒内等不到就 `fail`，写法与原有 `expectInboxEmpty` 一致。

## 失败率（本机 macOS，单测单独运行）

| 场景 | 次数 | 失败 |
|---|---|---|
| 基线 `develop` @ `b53d906` | 30 | 0 |
| 修复后 | 50 | 0 |
| 修复后 + 8 个 `yes` 加压（负载 6.3–29.8） | 20 | 0 |

本机复现不出基线失败；不稳定的证据来自云端沙箱（14 次失败 11 次）和 **GitHub Actions**（[run 37352148641](https://github.com/mightyoung/Muyon/actions/runs/37352148641)，`SocketException: Broken pipe`）。修复有效性主要由下面的探针支撑。

## 根因：同意
- 旧测试固定等 40 ms 后 `stop()`；慢机器上服务端还没读完请求，`_http.close(force: true)`（lan.dart:327）强关时客户端仍有未写完的 TLS 数据，写入得到 EPIPE（errno 32），而测试只放行 ECONNRESET。此时上传也还没进入 pending，旧测试并没有测到它名字说的场景。
- 探针（`git archive` 副本）：stop 时客户端有 1 MB 写入在途，**10/20 得到 EPIPE**，复现了原错误码；其余各组（未读请求就 stop、pending 后 stop、涓流写入）20/20 干净，stop 返回时收件箱都为空，stop 在 23 ms 内返回。
- **`stop()` 没有竞态**（lan.dart:315-330、584-702）：先置 `_stopped`；`_acceptPush` 的接纳检查（594）到 `_uploads.add`（610）之间没有 await；`_requests` 在 listen 回调中同步登记，快照取在 `_http.close` 之后，并等待 `_acceptPush` 的 finally（取消、关文件、删暂存）完成。发送方以 `on IOException`（lan.dart:872）统一处理，EPIPE 与 ECONNRESET 对用户表现相同，不需要改产品代码。

## 变异
| 变异 | 结果 |
|---|---|
| 删 lan.dart:328 `await Future.wait(_requests…)` | 5/5 失败（收件箱残留 `push-*`） |
| 删 326 与 328 | 5/5 失败 |
| 删 326 显式取消上传 | 0/5 失败，存活 |
| 326 改为 `unawaited` | 0/5 失败，存活 |

后两个存活是因为 `force: true` 关闭本身会掐断请求流，显式取消对这条测试是冗余的；原有特性，与本次修复无关。测试守住的是可观察保证：stop 返回前上传已结束且暂存已清理。

## 重跑
- `flutter analyze`（supplier_core）：`No issues found!`
- `lan_security_test.dart`：`+12: All tests passed!`；supplier_core 全量 `+482 ~3: All tests passed!`，与执行者一致。

## 只记录（可选）
- test:296-322：测试名说「cancels pending uploads」，实际守的是「stop 返回前上传已结束并清理」，可在注释中写明。
- test:113-114：「from then on no request bytes remain unread」依赖请求头与 1 字节 body 一次写出（`partial()` 现在如此），注释可补这个前提。
- 流程：核实开始时机器上有 32 个孤儿 `yes` 进程（约 3 小时，负载约 190），已清理。以后任务说明中的加压步骤一律要求用 `trap` 回收进程。
