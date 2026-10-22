# RD-P01 device-deferred pure domain candidate

2026-10-14. Writer: delegated `device_deferred_rust_domain`. Fixed base `b17ac548f7a8d2d6151cbdaf6af527722c67ee50`, branch `task/device-deferred-rust-domain-20261014`, worktree `/workspace/Muyon-device-deferred-rust-domain-20261014`. Root remains sole develop integrator; no product or integration branch mutation here.

User directed continued four-task parallel development with device verification deferred. Owned paths: `experiments/redesign/device-deferred/rust-domain/`, this document. All original SPIKE, apps/packages, root dependencies, M04 fixtures, M05 reference source and design checksums remain read-only. No shared writer paths.

Implemented a pure unpublished Rust crate for complete-raw UTF-16 name normalization and caller-supplied synthetic read/edit candidate validation. Exact local structs `ProvisionalSnapshot` / `ProvisionalEditCandidate` and reason enum are **provisional 0.0.0**, replaceable adapter seams. They do not freeze M03 DTO/wire/schema/digest/identity. Scope and ID are synthetic string equality preconditions, not authenticated IDs or authority. Same-name accepted candidate computes +1 without any effect. Snapshot is borrowed and immutable; failure paths preserve it. No persistence, receipt, intent/replay execution, grant consumption, FFI or model call.

Read contract `docs/contracts/redesign-v1.3.2/supplier-name-contract.md` and M04/M05 inputs/oracle. Implemented only settled limits: raw UTF-16 ≤2000, XML before trim/NFC, nonempty and ≤200 codepoints, no UI pretrim. Rust library `unicode-normalization=0.1.25` uses Unicode17; current cached Dart `unorm_dart 0.3.1` uses Unicode8. No global equality claim.

## Verification actually executed

- Rust1.99.0, offline cached dependencies with local lockfile and isolated `/tmp/rd-p01-target`.
- Genuine RED: 12 named behavior assertions fail against compileable stubs (not compiler/import failure); GREEN/restored GREEN: 12 passed, 0 failed, 0 ignored. Covers empty/200/201 codepoints, surrogate pairs/lone surrogates, raw-unit guard before trim, BOM/NFC/non-NFKC, XML boundary controls, internal whitespace, identity/scope/deleted read, revision mismatch/overflow and immutable candidates.
- Two local inverse mutations: remove raw limit, XML validation after trim. Each targeted test fails its intended assertion with Cargo exit101. Original source restored; no mutant committed.
- Actual unchanged Dart product oracle paired with Rust binary over all 32 fixed M04 name normalizer vectors: 30 equal outcomes/normalized values/reasons; 2 expected raw>2000 guard differences (old direct normalizer accepts, Rust new entry rejects). Source/hash and cached dependency checks pass. Not proof of tool/UI dispatch, model safety, cross-transport or all Unicode.
- Raw logs and invocation files: `/workspace/reports/device-deferred-rd-p01-20261014/`; sanitized `evidence/` summaries only in repo. README contains exact offline reproduction commands.

## Remaining gates

Android actual load **NOT_RUN**; real devices/release acceptance are deferred, still mandatory before related claims/releases. M03 **blocked_contract**, not all original exits passed. Must later freeze one authoritative representation, normalization version compatibility, scope/store/revision/digest and intent identity, recovery statuses, grant expiry/revocation and real transactional CAS/receipts. Real persisted read/write integration, authority validation, dedup/recovery, ABI/IPC adapters and device performance remain **NOT_RUN** here. Existing other experiment evidence is not counted as execution of these gates.

This work may proceed offline behind reversible local adapters without selecting a final runtime, adopting the local structs as product schema, accepting new license terms, or displaying mock candidate results as saved. Independent review and root candidate CI gate precede any develop integration. This task does not merge/push develop/main, forcepush, delete branches or deploy.
