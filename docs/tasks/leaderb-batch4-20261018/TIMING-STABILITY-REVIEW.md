# I02 / I03 timing稳定性与真实I/O：独立原件审计

结论：**scope C0，30轮默认并行统计及真实写入次数/时延的限定补证成立；无Critical/Important新增发现。** 可关闭“尚无数十轮样本”“只有静态双fsync/人为5ms机制、没有实际写次数时延数据”这两个限定证据缺口。不能据此宣布零flake、跨环境稳定性或历史失败精确根因已证。

产品精确F2 `3f1be180bb009a91e659c113ba5b1916e5360332`，tree `30ccb7d1ceda6fe66baeee0266ce961a57fd3e2e`。原件 `/workspace/batch4/evidence/timing-stability/`。本review只读原件/源码、计算哈希与汇总；没有构建、重跑整个队列、改产品/预算/线程、改design/memory/HY或启用writer。

## 来源与统计真实性

`FILES-SHA256.json`全部3580条独立逐hash符合原件；identity的runner/C探针/source .so/实际Rust binary哈希分别匹配保留文件。Rust binary为 `b3624c75a99cb83bd1b53f3fec5ce7403d98b2f09043955b3806a998aea5d6d5`。runner开始显式assert精确F2/clean、RUST_TEST_THREADS不在环境，再创建ENV；命令也无--test-threads/--threads覆盖。最终报告脚本再assert精确F2/clean。本review当前F2 clean，未将I05 test-only分支引入这些统计。

runner固定core1..30、wire1..30两独立队列，两个队列和I/O探针可并发，未发现重试/丢弃失败的代码或记录。每attempt的result.json记录command、退出、elapsed、分类及前后loadavg/CPU/uptime/io-pressure；环境资源快照四CPU quota units、五CPU affinity/cpuset、16GiB memory limit。压力条目null如实保留，不表示测得零压力。这是一次共享环境观测，不是隔离性能基准。

独立脚本 `audit_stability.py`读取全30份core raw，用F2正式full.rust combined逐group/name/status/summary重分类全部通过，每次115而非只信observed_passed。总3450个通过的测试执行实例不是3450个独立行为。30份wire原commands.jsonl每份恰12 start+12 run，四scenario happy/unicode/escaped-pair/crlf-comments ×三chunk8192/1/7实际完整遍历，共360个完成子场景。

每轮恰一次真实escaped-pair/chunk1 start与run配对，30次exit0/status completed/effects1/😀；从各task.db实际解码wire_config，total_ms5000/idle_ms2000/chunk1保持原值。不是method定义存在就计覆盖。

| 队列 | attempts | 非PASS | p50(s) | p95(s) | max(s) |
|---|---:|---:|---:|---:|---:|
| 完整Core115默认并行 |30|0|2.222704|2.278688|2.279432|
| 物理四scenario×三chunk整方法 |30|0|5.028774|5.854895|6.255903|

用全部30个elapsed独立排序并按nearest-rank第15/29/30项重算，与summary和independent-validation逐值相同。**第二行每个耗时包含12个子场景及24个CLI调用，是整方法wall time；超过5秒不等于单exchange违约。** 每个task的5000ms预算未改，实际所有run成功。结果记录无timeout/build error/测试失败，runner也区分这些分类；有限30次零观测失败，不证明真实失败概率为0。

## I/O探针真实性与独立重算

`io_probe.c`仅拦截真实write/fsync/rename：dlsym调用原函数，clock_gettime包围实际调用，保留原return/errno；事件使用原始syscall append到独立日志，thread-local busy避免递归。没有nanosleep、返回成功伪造、跳过fsync、合并保存或更改deadline。目录/临时文件通过/proc/self/fd读出的真实路径过滤，仅计本次task目录的.task.db临时写与目标task.db rename。实际时间包含系统调用当时调度，不是纯磁盘硬件延迟。

runner只在直接Rust run的enabled环境加入该probe .so；服务helper由生产WireProvider清环境。每个chunk有相邻无probe有效sibling，双方实际status/effects/😀/原receipt answer/模型调用/confirmations和sent/received/total counters相等。runner没有加入人工5ms延迟注入操作；此组和此前timing/candidate-built-F2人为5ms机制控制分别保留。

逐events.jsonl独立验证全部ns非负、fsync/rename result0、每次write result等于请求amount，并重算每种操作count、nearest-rank p50/p95、max/total，全部与independent-validation相符。四实际capture字节331、377、598、179按chunk上取整分别1485/214/4次I/O charge；加11个其他task保存，得到实际rename/write/file-fsync次数1496/225/15。这个11为本次观测的非charge保存残差，不外推为所有任务常数。

| chunk | task写/atomic rename/file fsync | task目录fsync | file-fsync p50 /p95 /max(ms) |
|---:|---:|---:|---|
|1|1496|1497|0.438019 /0.663519 /8.446050|
|7|225|226|0.477839 /0.856624 /2.726744|
|8192|15|16|0.693574 /3.876464 /3.876464|

目录fsync多1包含同目录effect提交，不计为task保存多1。真实原子保存源代码包含task文件fsync+rename+directory fsync，原probe测得的四操作序列和数量支持此次真实持久化成本放大，不是单纯静态grep或延迟模拟。每chunk仅一对probe/no-probe执行，分布中的1496等样本是同一次run内系统调用，不是1496次独立process实验。

探针有readlink、时钟与日志开销；baseline/probed wall time差不能在并发负载下精确归因为探针百分比开销。保留的每操作时延数据已经满足限定量化需要，但不能重建历史那次272/377B timeout的磁盘/调度轨迹。

## 子进程及停止范围

run_stability为直接命令新process session设置60s watchdog，timeout分支先杀已知descendants再killpg/wait；本次所有60attempt及probe无timeout。脚本作为subreaper最后adopted_reaped=[]，stopped-process-check=[]。本review从capture独立提取732个helper PID，当前/proc均不存在；各直接父命令exit0由runner wait返回。732是保留capture可见PID范围，不声称所有系统进程的完整清单；未启动长期后台server或新writer。

审计产物：`TIMING-STABILITY-AUDIT.json`、可复核只读脚本`audit_stability.py`（实际exit0）。未覆盖I04；其平台拒绝、NOT_RUN边界保留，不重试/换代理。I05真实SIGKILL限定证明另见I05-REVIEW.md。整套merge/draft、genericCI终态及归档由父/root处理，不由本统计报告批准。
