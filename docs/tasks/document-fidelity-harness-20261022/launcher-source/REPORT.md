# Launcher / authority / worker source delivery

本批完成 adapter/runner 的源码控制流程与 fake OS 验证，未完成真实宿主/内核后端/IPC，也未解除引擎 HOLD。没有 Rust、Android、生产 UI、main/develop 修改。

## Commits and scope

- Base: `6b796c8d6e094d45ef25e28698048c21ef0ae7b3`.
- Independently reviewed source: `f5a65182516fba1bafed542384019b28316cf768`.
- Final source after one author review-fix pass: `6f1ac828de642503dc1ec774fac9fa1023d873c2`.
- Final sealing commit only adds report/verification/handoff; full pushed tip is returned by execution response after remote readback.

实现：固定工作路径和 argv、只收紧资源策略、scope/source/request/engine artifact/worker/runtime hash 绑定、具体来源/许可/隔离评审证据接口、单次 admission/ready/worker/validator 能力、取消/超时/log/output 限额、TERM/grace/KILL/tree-reap、nonce 调和而不重试、unknown 隔离、reap 后稳定快照和原件/job/输出形态验证、现有精确差异 oracle、清理及终态撤销。注册表1024 attempts 满额拒绝而不丢弃 replay 历史。真实 OS 操作由未实现的受信 HostOSBackend 合约承接，没有 ambient subprocess 或替代隔离途径。

三个 worker 已从永远 raise 改为可信 worker permit 检查后才可进入的惰性导入/副本编辑源码。缺省 bootstrap 不存在，故入口 HOLD；这里从未执行 worker CLI 或第三方库。permit 路径不是普通 JSON 开关；未来真实 worker IPC 需独立认证绑定 staged context。

公共 receipt_version3 只供审计，不能凭 txn_eligible=true 提交。真实资格需独立 TrustedHostSession 核验；当前不存在该 provider。候选 bytes + 非 JSON 一次性 credential 的宿主消费提案在 DESIGN-AND-RECEIPTS.md，消费还需当前宿主 monotonic time/TTL。Rust 仍须原子复查取消、权限、scope、revision、idempotency 和 CAS；这里没有实现或宣称远端事务原子性。

## TDD and independent review

初始缺 API RED 原始日志 runner-red.log 保留。生命周期 RED 发现快照期间取消、ready 重复批准和 TERM 异常回收缺口；lifecycle-red.log 中 TERM 测试第一次误在子进程已退出后取消，已保留；lifecycle-corrected-red.log 修正为运行中取消后仍复现源码缺口，再 GREEN。

独立 reviewer 只读冻结提交，13 runner +60 legacy 通过，额外 fake OS/host 合约探针发现3项 P2：准备或清理后越 deadline、最后宿主验证期间取消仍放出结果、终态 lease 仍能签发 worker permit。完整原始复审/探针/日志在 evidence/independent/，未覆盖后续修改，不能称为新20项的独立复审通过。

作者统一一轮 TDD 修复：启动前/最终发布前后 deadline、宿主验证后取消复查与 credential 撤销、终态关闭 lease 并撤销预签发 worker/遗留 validator。补 credential TTL、严格 bool/proof shape、单次能力 mint 和有界注册表。review-red.log 为16项中3失败，ttl-quota-red.log 保留后续 TTL/容量负例。最终作者20 runner +60 legacy通过；原独立5探针的改断言作者回放全部通过（author-probe-replay.py/log）。

FakeHostOS/FakeHostSession 明确是测试可信应用接口的合成对象，既非真实宿主认证，也非实际 validator 凭据。它们没有安装生产 bootstrap；普通 simulation Authority/FakeOS、旧 simulated receipts 或 JSON 都不能升级。所有探针末尾 third_party_modules_imported=[]；真实引擎、沙箱、roundtrip、render/recalc 都为 NOT_RUN。

## Verification commands / exact results

| Command | Result / evidence |
|---|---|
| `python3 -m unittest discover -s tools/document_fidelity/adapters/runner/tests -v` | PASS exit0,20 tests; evidence/runner-final.log |
| `python3 -m unittest discover -s tools/document_fidelity/tests -v` | PASS exit0,60 tests; evidence/legacy-final.log |
| `python3 docs/tasks/document-fidelity-harness-20261022/launcher-source/evidence/author-probe-replay.py` | PASS exit0,5 repaired probes; candidate/credential withheld on cancel/deadline, post-terminal worker denied, expired validator denied |
| stdlib AST parse all adapters `*.py` | PASS; evidence/FINAL-VERIFICATION.json |
| `git diff --check 6b796c8d6e094d45ef25e28698048c21ef0ae7b3 HEAD -- '*.py' '*.md'` | PASS exit0 |
| Full raw `git diff --check <base> <source>` | FAIL exit2 only preserved original RED log trailing whitespace; evidence/raw-diff-check.log; no log sanitization |
| Fixture directories diff from base | Empty; original8 binary fixtures and3 manifests unchanged; hashes/environment in evidence/ENVIRONMENT.json |
| Existing repository `bash scripts/verify.sh` | Prior FAIL before suite: `flutter: command not found`, ../evidence/repository-verify.log; not repeated/installed |

Python3.12.14/Linux6.18.55. Remote Android candidate remains f4781e16ddf4e542b983fbd77f266a0071148255. Latest read-only UI check69b9cc3b6c5726006363bbf2add3b2564212731b has no changes in owned paths relative to fixed3ecb544ad0a47ccc38fe830777f35588b92e8afc. Original /workspace/Muyon worktree was clean and untouched. Final remote readback is recorded after push in the execution response.

## Remaining blockers and staged Office work

1. Exact known failed action: prior bwrap0.12.0 private namespace setup for harmless /usr/bin/true failed exit1 `setting up uid map: Read-only file system`. Known environment filesystem denial, not auto-review rejection. No engine started, no retry/relocation/alternate namespace/escalation; original ../engine-evaluation/evidence/isolation-attempt.log preserved. This remains denied environment capability, not pending approval.
2. Trusted HostSession authentication, real HostOSBackend and worker IPC provider are unimplemented/unqualified. Real no-network/RO mounts/limits/artifact pinning/process-tree reaping/stable no-follow snapshots have NOT_RUN kernel tests. Host/bootstrap/capability IPC must be independently reviewed and demonstrated in a compliant environment; no boolean/interface test can substitute.
3. Concrete artifact provenance/transitive/native/font license and isolation review evidence incomplete. Existing pinned engine candidates/license inventory remain in ../engine-evaluation/, no library installation/import/execution/EULA/fee/credentials occurred.
4. Narrow XLSX numeric/DOCX run/PPTX shape library compatibility and reopen/strict manifest/semantics still NOT_RUN. XML serialization5.0→5 remains failure, no unproved equivalence. Real engine output may be unsupported by strict preservation oracle. Formula write does not establish recalc.
5. PDF parser/render/editor, public readers/annotations, wider document features, render/visual/recalc and core/txn/UI integration remain future stages. Four-format Office capability is not complete. Leader B alone may merge develop after separate review.

Historical two unknown model requests and ¥0.002620 reservation were not retried or changed. No paid/model/search requests, real user documents, external document transfer, software/security configuration changes, deploy/merge/force push/delete were performed.
