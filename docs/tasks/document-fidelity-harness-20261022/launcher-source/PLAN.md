# Small source slices and ledger

Base6b796c8d6e094d45ef25e28698048c21ef0ae7b3. Design/receipt proposal written before code. Own adapter/runner and independent docs only. All tests fake OS; no library/worker CLI/namespace execution.

- [x] Slice1 TDD trusted host evidence/lease/binding expiry, strict scope/artifact/policy ids, simulation assurance and non-JSON one-use validator credentials. Default missing/current environment HOLD.
- [x] Slice2 TDD complete controller with fake OS prepare/ready/spawn/poll/output/cancel/terminate/grace/kill/reap/snapshot/oracle/cleanup/quarantine/reconciliation. Every denial/uncertainty fail closed, no retries. Scope-bound receipt3 and sim-vs-real credential separation.
- [x] Slice3 permit-check live worker source bodies (no unconditional forever-raise), bootstrap-less CLI HOLD, compatible real entry delegating only through trusted runtime binding. Tests verify JSON/simulation/expired/mismatched permits reject before engine import. Full old/new tests, fresh independent review/fix pass, evidence/docs/task-only push.

Ruling: do not implement a weak ambient subprocess or alternate namespace backend to make tests green. External trusted host verifier/qualified kernel backend/worker IPC integration remain explicit unimplemented prerequisites; full lifecycle source and fake OS tests can be completed without executing them. Cost: current real execution remains HOLD and kernel effects are NOT_RUN.

Independent frozen review:13 runner+60 legacy tests,3 P2 findings. One author TDD review-fix pass: deadline/cancel release gates, terminal revocation, credential expiry and bounded registry; final20+60 tests and original five-probe author replay pass. Not an independent rerun of20. See REPORT.md/evidence.
