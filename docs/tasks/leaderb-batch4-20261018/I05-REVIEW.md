# I05 真实SIGKILL：独立补证审查

结论：**scope C0，所列两个确定窗口的真实SIGKILL缺口已补证；未发现需产品修复的Critical/Important缺陷。** 不外推随机crash、内核recv内部kill、电源故障、所有业务 exactly-once 或whole-F2测试通过。I04仍NOT_RUN；未重试被平台拒绝的操作，没有换代理。

产品锚点F2 `3f1be180bb009a91e659c113ba5b1916e5360332`；实际执行proof SHA `a0ec87ba5f107b5905204ac2d5bd731d19f96503`。代码工作树 `/workspace/batch4/i05` clean。唯一diff为`experiments/redesign/rust-agent-host-lab/core/src/http_recovery_tests.rs`末尾追加188行，原F2文件前缀逐字节相同；git diff仅此文件+clean索引证明其余2750个tracked文件与F2不变。模块由`core/src/lib.rs:670`的#[cfg(test)]约束；没有生产源码修改。proof不等同whole-F2，未合入/push该补证。

## 独立原件核验

证据 `/workspace/batch4/evidence/i05/`。159个sha256sums.txt条目逐文件重hash全部相符；probe-source.rs与实际proof源码字节一致，F2-original源码与git show F2:path一致。metadata的test source SHA `c63c6c89f3220e2040149444abd79e9c092b1ae7cafb77f2bb2136b29fdd6863`、F2原test SHA `c4f17b7ea58e31590ac88f19397369a9ba2bf2db46b8362b52ffb3a4d99a7228`与实际文件相符。binary原件亦可取得，独立重hash `4fc6ff7ef4ac5873371271d6c734c3bcb002607b84f776b421e887116b9c3f0b`符合metadata。

首轮run.log实际1passed/8filtered；模块regression.log为7passed/2filtered。模块7中包括两个无环境时早退的child入口，不能将其当7个独立杀进程行为；真正补证由外层loopback_real_sigkill_windows_and_healthy_sibling实际spawn并等待三组子进程实现，两轮均有完整网络/信号/恢复原件。

首轮和模块回归的begin/io中，task.db.before与after_child真实字节相等；before provider_inflight=true，begin sent/received0/0，io312/83。恢复后task身份/counter不变，状态变为outcome_unknown/wire_interrupted；task.db允许恢复时保存这一状态，不冒称其全字节不变。两次恢复的outbound.db/native.db与before、after_child、after_recovery原字节相等。健康同wrapper完成、answer complete，reopen completed且model_sends0。两轮listener恢复后无新增accept；IO实际request312B、response83B/完整174B。cleanup.json18个owned PID记录不存在，本review当前/proc复查也全不存在。

## 真正生产链路及屏障范围

- proof `http_recovery_tests.rs:237–243`的KillEndpoint包裹真正LoopbackEndpoint，其validate_session直接转发，exchange读取真实outbound begin后进入测试barrier，释放后调用真正inner.exchange。
- 原F2 `model_gateway.rs:60–95`实际respond_controlled先validate/review/atomic ledger(begin)，再final admission与endpoint.exchange；原NativeStore::ledger使用core store::atomic，原atomic包含file sync_all、rename、directory sync_all。wrapper不写outbound/task/native“预期成功状态”；ready/release和original-identity是独立测试观测文件。
- proof `:221–234` KillControl转发poll/remaining/checkpoint，charge先执行原inner.charge，返回后才State::load校验received和inflight、读取真实ledger并阻塞。原F2 AgentControl::charge更新真实计费并save_drive落盘；真实TCP HTTP请求/partial recv来自原Loopback transport。IO屏障在真实recv且持久charge返回后，**不是内核recv系统调用内**；父侧只发送前83/174B，完整响应未送达。
- proof `:253–275`恢复直接原目录Agent::open/NativeStore::open，不调用initialize、不建替代task、不重写ledger；两次drive并open保留原task/attempt/counter，model_sends0。父端listener无新增accept提供独立网络佐证，未只信内部计数。
- proof `:302–398`拥有真实Child PID并调用Unix Child::kill/ExitStatusExt::signal()==9，wait回收；没有把process::exit(73)、panic或人工ledger故障称为SIGKILL。8s测试barrier、5s观察/恢复wait以及socket3s读timeout使正常路径有界；子进程不再spawn其他进程，Drop kill/wait负责失败回收，listener归父测试栈，无后台server writer。

测试暂停会改变自然调度，但不取消begin已sync或recv/charge已sync的事实，不隐藏SIGKILL后恢复行为。它精确证明两个受控持久化点的恢复合同，不证明两个点之间每条机器指令都经过随机故障注入；也不证明掉电/fsync硬件语义。本fixture为纯问答、native无业务效果；不能泛称所有工具副作用的幂等性完成。

## 本review独立最小重跑

未重建、未跑全量，使用上述已独立核hash的实际proof binary：

`MUYON_SIGKILL_EVIDENCE=/workspace/batch4/evidence/review/i05-independent /workspace/batch4/i05-target/debug/deps/muyon_rust_agent_host_lab-486f53ad8f574b9e --exact http_recovery_tests::loopback_real_sigkill_windows_and_healthy_sibling --nocapture`

实际exit0，1passed/8filtered，0.05s。原件 `I05-INDEPENDENT.log` 与 `i05-independent/`。

| 独立场景 | owned child / recovery | 观察 |
|---|---|---|
| begin |43446 /43448|真实SIGKILL9/-9；begin已落盘、0accept；两次reopenunknown、0发送/接收、无新accept|
| IO |43450 /43452|真实SIGKILL9/-9；request312B/response83of174B；durable sent312/received83；两次reopenunknown、无新accept|
| healthy |43454 /43456|exit0/complete，完整174B，reopencompleted，model_sends0，无新accept|

独立运行新六个PID均由父wait回收且/proc不存在，记录 `I05-INDEPENDENT-CLEANUP.json`。未影响全量/计时门禁、未修改源码、未commit/push/merge。

父/root可将I05“真实begin后及partial-IO持久charge后无SIGKILL证据”限定缺口记为已补。原exit73和人工路径破坏仍保留原性质，不因新增proof重命名。该proof自己的SHA、binary和日志必须独立引用，不能嫁接成F2正式CI或更大范围产品验收。整套draft与I02/I03/I04等范围另由父/root处理。
