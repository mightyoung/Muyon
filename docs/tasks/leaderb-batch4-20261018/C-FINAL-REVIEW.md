# C timing：独立代码与证据复审

C固定提交 `7b0980b5ac66bea932a0c1028f873b25e2307054`，父合入 `6e8c5e3fc73d520e0c070c66a5bdfb00145a1b01`，最终候选 `a3ee7df596b0375aa9f3e6ff4c7651efd5f778a0`。审查员/root/review，未改源码、提交、push、merge，不是Claude审查。A由另一reviewer负责，本报告不认证A。

结论：**scope C0：该测试同步/清理修订可进入隔离实验组合验收；无Critical/Important合入阻断。** 保留100ms idle、500ms该测试total、5000ms物理wire total及durability；不宣称5000ms历史失败原因已确定。辅助诊断脚本失败路径watchdog不完整，属非正式gate改进项，不能宣称全路径owned cleanup。

## 独立实际执行

在最终a3ee7df的clean integration，以独立 `/workspace/batch4/evidence/review/minimal-target` 编译并执行：

`cargo +1.99.0 test --offline --locked --manifest-path experiments/redesign/core-agent-lab/core/Cargo.toml --test wire silent_and_eof_hanging_children_are_killed_and_reaped -- --exact --nocapture`

exit0，1 passed /26 filtered，0.86s；实际日志含silent/eof-hang普通、150ms延迟两个子场景及drop_at_checkpoint第五子场景。完整日志 `C-FINAL-MINIMAL.log`。未重复完整suite。最终同次Python discovery 37 tests、0.604s、OK；新旧分类器控制均通过。前后git status clean。独立git diff确认 d25..最终候选 core/src 零差异。

## 代码判断（路径均在C固定SHA，最终对应内容相同）

- `experiments/redesign/core-agent-lab/core/tests/wire.rs:112–179`：新同步等到实际helper PID存活、hold-ready内容与wire-open checkpoint同时出现，再释放Rust，不凭预期延迟猜测helper启动。保留effects0、timeout reason、/proc PID消失断言；新场景没有移除原silent/eof-hang两个行为。
- 同文件`:119–131` OwnedRun持有Rust Child，进程组由process_group(0)建立，Drop先关闭checkpoint stdin释放EOF，最多轮询2s，再向仅该run组发SIGKILL并wait回收Rust。正常路径在Drop前已检查helper不存在，不能用fallback将产品泄漏洗绿；异常drop子场景另验Rust和helper消失。readiness与completion分别5s有界。最终wait在SIGKILL后等待，不是针对不可杀内核D状态的绝对硬时限，正常用户态范围足够。
- `core/src/wire_provider.rs`（d25和最终相同）deadline在Python spawn前创建；wire-open位于写完request/drop input后。checkpoint不改配置时间，超时检查仍由原loop执行。同步验证的是实际达到hold后的清理，不能抬升为“helper就绪后完整测量新100ms窗口”；TIMING.md已明确这一边界。
- `timing_fsync_delay.c`每次fsync先nanosleep5ms再调用真实fsync；无绕过durability或chunk限额。`timing_diagnostics.py`复用escaped-pair原fixture与5000ms/2000ms，核真正字节、效果、回执与reopen不重发，不计为正式物理验收替代。

## 原始证据独立复核

已逐项重新sha256核对 `/workspace/batch4/evidence/timing/original-sha256.txt` 三原件全部相符：Batch3 full-core、wire_process.log、commands.jsonl。原full-core panic为wire.rs:110:356 ENOENT，原wire失败为escaped-pair/read_bound1，总5000ms、sent331/received272/emitted377、wire_total_timeout；不能将其改称cleanup断言失败或模型/HTTP失败。

- `pid-red.log` SHA256 `529936645de37872651a2e32ded51c1b5fbf2ce1e27a2f57e203696356c8d8c0`：同名目标实际ENOENT/1 failed；`pid-green.log`是四场景开发GREEN，不冒称五场景最终；最终五场景另在final-pinned-regression.log且本review最终SHA又实跑通过。
- `cleanup-inverse.log` SHA256 `fe91642615dfc99d6e31280ae82595f451825fed7919caeeff9cc0f5298a818c`：真实compiled目标在child must be reaped断言失败；`cleanup-inverse.json`exit101；外部negative harness实际adopted/reaped一个status9 helper。其forced kill只清理负对照，不记为产品正常成功。
- io-run-1/2/3 的controlled-io.json均6对照：无注入8192/1/7和注入8192/7均completed；注入chunk1分别约5.041/5.040/5.046s，wire_total_timeout，received101/117/111且effects0。它证明可复现机制，不能证明历史盘延迟/调度事件。三个identity均记录d25 HEAD与同一debug binary SHA `8fbec738a80840ba57ffce39df651444811e2fe2226b44fa6eddf8bfcf147c06`，文档明确当时测试树dirty；不将HEAD标签读成clean whole-source执行。
- core-full.log正文独立库存审计115，physical-process.log26方法，physical-wire.log18方法；完整原记录含各自成功summary。审计保存在 `C-LOG-AUDIT.json`；该审计传入作者报告退出0，不是独立进程重跑/退出元数据。无重复full。
- 四个final-test-sources.sha256均与C worktree文件相符。独立重算release binary SHA `b3624c75a99cb83bd1b53f3fec5ce7403d98b2f09043955b3806a998aea5d6d5`与记录相符；physical旧日志同hash。源码同一性与二进制同hash仅支持runtime复用边界，不使dirty实验变clean final candidate结果。

## 限制/非gate改进

`timing_diagnostics.py:27,31,44`：start/reopen subprocess未设timeout；主run虽timeout20，但TimeoutExpired只保证直接Rust进程被杀/等待，没有新process group或helper组清理finally。当前已成功六对照未触发此路径且观察helper退出，不使既有证据无效；这只是不应宣称通用故障watchdog。未来重用诊断工具可补每步有界与owned cleanup；本批无需因此扩大测试修复、阻断实验合入。

当前已见causal仅io-run-1/2/3；TIMING.md称final pinned causal另存，目前尚未提供该独立路径，已告知父/root。此报告只认证已见三轮机制证据和实际最终单目标回归，final-SHA causal仍pending，不由文档句子补造完成。

最终门禁CI、全量组合结果及Android同源产物由父/root汇总另审；本scope C0不等于整套合入授权。无审批拒绝或待重试操作。

## exact-F build/causal 补证复审（关闭上文final causal pending）

后续固定证据目录 `/workspace/batch4/evidence/timing/candidate-built-F/` 已核实。`build-provenance.json`实际command为clean final `a3ee7df596b0375aa9f3e6ff4c7651efd5f778a0` 上调用cargo +1.99.0 build --offline --locked --release，exit0；before/after SHA、tree、clean status、全部26个source hashes与binary hash一致。独立逐source核对当前文件和`git show F:path`字节全部符合。build.log SHA `e47e4ce5863cfa0380c6d6d1c4fe4a9cbd0898510beb99c5528f23f0f7815359`独立相符，实际日志明确Finished release in0.01s（外层elapsed0.055s）：真实构建调用允许Cargo cache复用，**不称无缓存重新编译**。

随后`diagnostics-provenance.json`记录用该actual output路径在同一clean F运行诊断，exit0，after_source_sha仍F/after_worktree_status空。独立核验product hash仍`b3624c75a99cb83bd1b53f3fec5ce7403d98b2f09043955b3806a998aea5d6d5`，diagnostics.log SHA `a65e6ac79f6af816bc693602ec8ea050b2001bbcaa3fad29b17a1ccf2488fe2d`、controlled-io.json SHA `a364be658e6b86e8211f90cc2a70a992570fda34108c57e8431b38b4a233fbbb`均与文件实际字节相符；总provenance里的两个followup JSON hash也相符。

六实际对照：无注入chunk8192/1/7分别0.062/0.889/0.157s completed；注入chunk8192/1/7分别0.181/5.035/2.524s，只有chunk1 failed/wire_total_timeout，sent331/received117、effects0；其余五案effects1与完整follow-up/receipt。脚本成功路径同时执行helper退出和失败reopen无重发断言，stopped-process-check.json为[]。这补齐**clean F实际构建调用之后的causal driver六组执行证据**，不再仅靠先前同hash旧binary实验支持最终来源。

因此上文“final-SHA causal pending/路径未见”的时点限制已关闭；原三轮dirty实验与等价runtime旧binary实验完整保留且没有重命名为本次构建。历史5000ms失败的精确归因仍未知，辅助诊断失败路径watchdog限制仍保留；本补证不改变scope C0、不认证尚未核完的整套CI/Android结果。本阶段审查停止，等父/root汇总最终CI与A证据后另作整体结论。

## exact-F2 独立补证复审

新最终候选 `3f1be180bb009a91e659c113ba5b1916e5360332` 的 `/workspace/batch4/evidence/timing/candidate-built-F2/` 已独立审，不沿用F证据。build-provenance before==after，精确F2/tree30ccb7d1/clean status相符；每项source hash既与当前clean F2文件相符又与git show F2:path blob相符。pid-regression与release-build实际command均exit0，各自log hash核对；Cargo cache reuse明确允许，不称无缓存重编译。release产物仍为b3624c75a99cb83bd1b53f3fec5ce7403d98b2f09043955b3806a998aea5d6d5，实际文件独立重hash相符。

F2 diagnostics-provenance记录exit0/sourceF2/after_worktree_clean true；diagnostics.log SHA256 `1fde694f0f771d64c7ac623920725bca6c9becdff470ec28db087b9778418a81`、controlled-io.json SHA256 `18351c3dd0773d4d001a04aaae7a2d249df527616116f39ea9a3358a85d30080`均独立重hash相符。六组新对照无注入8192/1/7分别0.060/1.000/0.127s complete，注入8192/1/7分别0.180/5.039/2.530s，只有chunk1 failed/wire_total_timeout、sent331/received119/effects0，其他effects1；stopped-process-check为[]。这些是F2实际driver执行，不是F结果重标。

维持C测试修订/机制实验scope C0；I02默认并行重复统计、I03写次数时延量化、I04旧script HTTP恢复复现、I05真实begin后/IO中SIGKILL不由此六组diagnostic完成，历史失败精确归因也仍未知。整套merge保持draft，等待其余范围实际验收与父/root决定；未改产品或design/memory内容。
