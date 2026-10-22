# 冻结源码独立复审

冻结提交：`f5a65182516fba1bafed542384019b28316cf768`；比较基线：`6b796c8d6e094d45ef25e28698048c21ef0ae7b3`。范围为 runner、三个 worker、runtime 以及对应设计。审阅期间没有修改或提交仓库源码。报告、额外探针、日志均位于本目录。

结论：发现三个 P2 控制流/能力生命周期问题，建议在未来生产接入前修复。当前无真实 HostSession/OSBackend/可信 IPC，默认真实入口仍 HOLD；没有证据支持真实 sandbox/credential/Office 能力，也没有发现普通 JSON 或 simulation 可直接提升为生产资格。以下 synthetic host 探针只是显式 fake OS 单元级验证：FakeHostSession 故意返回合成 evidence，使源码宿主分支可观察；绝不是生产 verifier、真实宿主资格或 OS 隔离证据。FakeHostSession 直接调用可信应用 bootstrap API 建立合成对象；不是从普通 FakeOS 或 simulation 回执升级，更不是从 JSON 获取授权。

## P2-1：启动和最终发布只检查 lease TTL，遗漏操作 deadline

位置：`tools/document_fidelity/adapters/runner/launcher.py:112`、`:118`、`:156`、`:181`、`:199`。

操作 deadline 以 admission 前的 `start + policy.timeout_ms` 为准，但 spawn 前仅检查 lease TTL。Simulation lease 明确比 timeout 长，宿主 evidence 也可在 60 秒内给更长 TTL。准备/ready 已耗尽操作预算时仍启动引擎，之后第一次 loop 才发现已超时。最后一次 deadline 检查位于 validation 后、terminal_proof/cleanup/最终 verify_terminal 之前；这些步骤消耗剩余预算时，issue_credential 只检查更长的 lease，因此已经超过操作 deadline 仍发布 candidate/credential。

复现：`python3 /tmp/launcher-independent-review-f5a6518/probes.py`，第一及第三条 JSON：

- timeout=50，FakeOS.ready 将 clock 置51，调用序列仍是 reserve→ready→spawn→terminate→reap→cleanup，最终 timed_out。
- 显式 FakeHostOS.cleanup 将 clock 置51，最终 candidate_validated、txn_eligible=true、candidate_returned=true。

影响：已过期任务仍可产生新进程或可提交候选；最终状态与受策略约束的 deadline 不一致。建议为启动、快照/验证前和最后发布设置统一 deadline 检查，且在可能阻塞的宿主验证后再次检查；deadline 必须与未来 backend 的实际硬预算一致。

## P2-2：最后宿主验证发生取消后仍返回可提交结果

位置：`tools/document_fidelity/adapters/runner/launcher.py:190`（最后取消检查）、`:199`（调用宿主 verifier）、`:203`（接受并返回）；`authority.py:127`。

最后的 cancelled() 在 issue_credential 前检查；issue_credential 内部可调用耗时宿主 verify_terminal。若此期间取消状态变为 true，源码仍接收 credential 并返回 candidate_validated、txn_eligible=true，无复查或撤销。

复现：显式 FakeHostSession.verify_terminal 设置 session.cancelled=True，并返回与请求/receipt/candidate 精确绑定的合成 evidence。探针第二条 JSON：cancelled=true，但 candidate_returned=true、credential_returned=true、txn_eligible=true。

影响：控制器已知取消接口存在，但最终发布窗口仍可越过取消。建议明确宿主发布的线性化点，最后验证后重新检查取消/deadline；若先 mint 后发现取消则必须使该 credential 无法消费。未来 core 消费也应和 scope/revision/idempotency/cancel 状态核验结合，避免仅靠新增一次非原子检查来宣称消除全部竞态。

## P2-3：终态未关闭 lease，取消清理后仍能签发/消费 worker permit

位置：`tools/document_fidelity/adapters/runner/authority.py:71`（check_lease 无终态）、`:101`、`:114`；`launcher.py:172`、`:180`、`:205`（终态清理/返回无 revoke）。

claim/ready/mint 都分别有一次性标记，但 Authority 没有 close/revoke 的终态，worker record 也不关联父 lease 的终态。controller 在 cancelled/failed/outcome_unknown/cleanup 后均不关闭 lease。只要 TTL 仍有效，延迟 broker 回调可继续签发该已结束 attempt 的 worker permit，并消费它。已有未消费 permit 也没有父状态校验可以撤销。

复现：FakeHostOS 保存 spawn 收到的 lease。运行时取消，源码完成 reaping 和 cleanup 后，调用同 authority.issue_worker_permit，再调用 consume_worker_permit（只调能力 API，完全不执行 worker）。探针第四条 JSON：status=cancelled、cleaned=true、permit_issued=true、permit_consumed=true。

影响：源码单次 ready/claim/mint 无法表达“任务已经终结，不能再授权 worker”的生命周期约束；延迟/并发 IPC 集成可能在取消或隔离后继续授权。建议终态与所有 permit 的撤销在 Authority 锁内统一管理，消费必须检查父 attempt 仍处于允许 worker 的阶段。生产桥还需把 permit 绑定到该 attempt 的实际 staged context；固定路径字符串本身不能证明当前 sandbox。

## 非阻断观察与边界

- Validator capability 的 consume_credential 无 now/TTL 参数，validator record 没有 expiry；probe 第五条 JSON 显示 admission expires=1000 而 fake clock=1000000 仍可首次消费。设计明确要求 scope/revision/idempotency 在 Rust commit 重验，尚未明确 credential 自身是否继承 TTL，因此本项不另算缺陷。应在未来接口契约明确：永久有效的一次性 validation evidence，还是有期限的授权能力；不可将这里的 consume 当作当前权限有效性检查。
- Public JSON 只是 audit data；普通 dict 无法满足 Capability、TrustedRuntimeBinding、TrustedHostSession 等类型边界。Simulation route 无 credential、txn_eligible=false；worker permit mint/consume 拒绝 simulation。未发现旧 receipt 或 forged pass JSON 能直接启动真实引擎。
- 快照在 reap_tree=True 后进行；candidate 被捕获为不可变 bytes，检查 source/job 一致、regular/link_count/output shape，再由现有 oracle 验证。未发现当前 bytes 返回路径的文件替换发布竞态。但 stable no-follow snapshot、实际进程树清空、RO mounts/网络禁用/资源限制仍全部依赖未来 backend，单测不能证明。
- 异常 stage/spawn 会按 attempt reconcile，不能证明 ownership/reap 时 outcome_unknown+quarantine，未看到自动重试。TERM 异常继续 KILL+reap 的已有测试通过。
- Authority 的 _records/_attempts 无回收；在长寿命服务大量请求时会无限增长。暂作为未来服务集成/容量观察，建议与 terminal revoke 同时设计过期回收和防 replay 的有界持久机制。

## 验证与原始证据

- `runner-tests.log`：`python3 -m unittest discover -s tools/document_fidelity/adapters/runner/tests -v`，13 tests，OK。
- `legacy-tests.log`：`python3 -m unittest discover -s tools/document_fidelity/tests -v`，60 tests，OK。
- `probes.py` / `probes.log`：五条控制流探针，所有断言通过；末行 `third_party_modules_imported=[]`。
- 未导入/执行 openpyxl/python-docx/python-pptx 引擎，未执行 worker CLI，未操作 bwrap/unshare/其他实际隔离，没有安装、提权、网络凭据或系统修改，没有重试或绕过已知 bwrap UID-map 拒绝。
- 复审开始时 git status 为空；结束时出现 HANDOFF.md 和 evidence/ENVIRONMENT.json 两个未跟踪文档，非本复审写入。本复审只写本 `/tmp` 目录。

真实 HOLD 是硬边界，当前缺失真实宿主/OS/IPC 的情况仍是生产验证阻断，不能因源码单元测试通过而解除。
