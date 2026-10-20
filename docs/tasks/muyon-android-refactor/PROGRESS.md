# Execution ledger

Target: all 21 reviewed task cards. A local implementation/test result does not close API26 or live-provider acceptance.

| Task | State | Evidence / remaining gate |
| --- | --- | --- |
| P00 | IN_PROGRESS | Isolated branch based on cebc6876, source ancestry recorded; final immutable candidate/hash pending. |
| P01 | LOCAL_PASS | Strict Rust contract/schema/fixtures; 10 tests passed. Kotlin uses generated UniFFI surface; final device semantics pending. |
| P02 | IN_PROGRESS | New crates and apps/muyon_android product tree; real ARM64/x86_64 bundled-SQLite builds; hash-bound APK packaging in verification. |
| D01 | VERIFIED_TARGET | Commits 944e18b0/7039175c; two deterministic RED-to-GREEN guards, 34 Rust tests and API26 original two Settings→Send tests pass. See D01/. Does not prove new product/live provider. |
| D02 | BLOCKED_HOLD | Existing I04 denial preserved; read-only artifact hashes verified, missing acceptable runtime evidence. No equivalent retry performed. See i04/. |
| P03 | LOCAL_PASS | Real SQLite atomic effects/receipts, real SIGKILL recovery and three isolated behavior mutants; 12 business tests. See core-store/. |
| P04 | IN_PROGRESS | Private :core Service, bound sessions/owner epoch and visible confirmation; no model dispatch to authority. Device lifecycle/cancellation proof pending. |
| P05 | LOCAL_PASS_REVIEW_PENDING | Upload/read pins, same-transaction reference publication and recovery; 19 tests incl. 10 actual SIGKILL windows. Independent review pending. See blobs/. |
| A01 | LOCAL_PASS_REVIEW_PENDING | Restricted ZIP32 metadata, 13 tests, real Dart ZIP round-trip fixture and three guard mutants. Platform DEFLATE/device proof pending. See archive/. |
| S01/S02 | LOCAL_PASS | Full eight-field supplier CRUD/soft delete/restore/reference policy persisted in real DB; Android UI acceptance pending. |
| R01/R02/R03 | IN_PROGRESS | Source-bound immutable snapshots and real PDF catalog implemented; first 11 Rust integration tests pass; final checks/review/device pending. |
| U01 | COMPILED_DEVICE_PENDING | Real Service-backed supplier Compose screen and two instrumentation tests compile. |
| U02a/U02b | IN_PROGRESS | SAF streams/private upload, frozen ZIP reader and platform PDF display implemented; tests/build/device pending. |
| C01 | IN_PROGRESS | Product owner, separate persistent budget ledger, strict transport/cancellation gate and local parser tests implemented; schema3 model-tool scope/disclosure/P04 suggestion loop is being integrated. Production price verifiers remain None; no real paid calls authorized. |
| V01 | IN_PROGRESS | Official ARM64 API26 AVD actually booted (SDK26/arm64-v8a); new product candidate/UI run pending. |
| V02 | PARTIAL_LOCAL | Real SQL/file/SIGKILL tests pass; complete installed-product lifecycle/unknown-outcome evidence remains open. |
| V03 | PENDING_HOLD | Final review, candidate seal and all acceptance gaps required; D02/live gates cannot be relabeled green. |

No task is marked complete solely from files existing or historical CI results. D01's API26 result concerns the reused original lab stack. New product API26 UI and real-provider acceptance are separate gates.

## Latest provisional device evidence (2026-10-21)

- API26 ARM64 real product: seventh run passed 9/10 tests. Valid/malformed Unicode,
  same-process owner reopen, saturated close, supplier CRUD and research PDF/DEFLATE
  import/paging passed. Recovery pagination assertion correction awaits the next build.
- Actual device fixes: replace SELinux-denied hardlink publication with private
  copy/fsync/rename; reject incomplete schema1 rather than silently creating tables;
  explicit business-v2 namespace preserves old unknown rows; reject malformed Java
  strings before UniFFI handle cloning. See product-device/ and core-store/ incident notes.
- System picker is not yet accepted: actual DocumentsUI PDF selection still fails in
  the provisional test helper; debugging continues against the real UI tree.
- Final same-candidate suite, source seal, full lifecycle scenarios, I04 evidence and
  live provider/price evidence remain open. Earlier task-table device states above
  describe initial implementation checkpoints and must not be read as final acceptance.
