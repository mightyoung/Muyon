# Ordinary chat wiring — bounded outcome

Draft [PR95](https://github.com/mightyoung/Muyon/pull/95), stacked PR94. Tested source **fbde72aa0420c522a94417f383ec17a8d0718677**; implementation **cbc03836** (subsequent freeze was docs-only). Sole LeaderB integration. No merge or HOLD release.

## Actual implementation

Existing Compose Send now submits ordinary-chat-v1 (conversation/text/request) through private Binder Service and genuine UniFFI to the existing Rust controller/worker and the same core Agent::run_with_runtime_ports drive. It binds current workspace/conversation, actual task/attempt and run:request input_ref without invented supplier selection or grants. Supplier read keeps its original source owner.

Versioned finite input/output scans, trusted source restrictions, full provider profile/policy/grant, conservative synthetic total budget and generation-bearing opaque capability accompany exact frozen payload. The same durable owner pins exact context/capability before final admission, compares them again at handoff and persists a one-shot attempt before the no-network fake exchange. Interrupted/uncertain sends never automatically retry. Strict restored evidence checks closed schemas, rule/input versions, actual identities, profile, usage and budget boundaries. UI completion supports a provider receipt without a supplier projection. Default Application installs an unconfigured owner and denies missing facts; synthetic installer/fake exchange exists only in the ordinaryChat build.

No production authority/provenance/credential capability installation or real transport is supplied. Existing v2 mixed/old journal migration is not verified. Scanner coverage is finite and can miss arbitrary unlabeled secrets. FullAllow/Auto decisions are settled; none are newly deferred or given reviewer/taint/endpoint questions.

## Verification

- Local explicitly named Rust target: **6 PASS**, 0 failed after root inventory repair. Covers ordinary frozen bytes/same Agent, duplicate/no resend/disclosure revocation, credential input/output, handle rotation before/after commit, quota, tampered usage/profile evidence, missing owner and revoked grant. These are controller tests, not Compose device evidence.
- Actual UniFFI build/generation/cmp: PASS after correcting private Json import and unsupported callback defaults. Package-helper AST: PASS. Existing core read/write runtime-symbol warnings remain.
- [CI39144821029](https://github.com/mightyoung/Muyon/actions/runs/39144821029): terminal **FAILURE**. scoped (same six Rust tests + binding reproduction), native arm64-v8a, native x86_64: SUCCESS. package-device job: FAILURE, with `Build fixed offline chat APK` SUCCESS (assemble app/test APK, lint, strict API26/ABI/no-INTERNET package inspection) and `API26 exact Compose Service Agent ordinary chat` FAILURE. Upload-artifact step succeeded. No cancellation or rerun.
- **Ordinary chat synthetic Compose→Service→same Rust Agent→plain response→same conversation E2E: NOT VERIFIED.** Two named device tests were selected by the workflow, but the failing step does not establish either individual outcome. Do not mark them PASS or invent per-test NOT_RUN. The exact failing cause is unknown. That one step includes SDK installation, AVD creation/boot, APK installation, instrumentation and grep validation; metadata does not even prove instrumentation started.
- New direct raw log read job **117726786359** attempted once, returned storage **HTTP403**, stopped. No retry, artifact/alternate download or environmental route change. Independent primary check annotations only say `Process completed with exit code 1.` No raw instrumentation log, PID, actual receipt or device output is locally archived/claimed. Run/jobs/steps/annotations and precise denial are in evidence/.
- Local initial/private-visibility compile failure, bridge private-Json failure, extended native 5PASS/1FAIL and quota diagnostic, and unsupported-UniFFI-default build failure all remain archived. Their corrections do not overwrite failure evidence.

## Reviews and remaining blockers

CONTRACT-REVIEW, GRAPH-REVIEW, NATIVE-REVIEW, FINAL-GRAPH-REVIEW, SOURCE-REVIEW, repair reviews, FINAL-SOURCE-REVIEW, EXECUTION-REVIEW and FINAL-COMPAT-REVIEW identify exact immutable sources and execution boundaries. Initial review found actual context/persistence/evidence gaps; repairs were independently reviewed. Source approval is not runtime success. All source writers stopped. Final archive/claims review is read-only except its report.

Immediate blocker: access to this new job's failure evidence is denied. Completed independent work is source implementation/review, six controller regressions and passing native/APK/lint producers; actual device E2E remains unresolved. Resume only with newly authorized/available diagnostic evidence, without retrying the denied log operation or downloading it by another route. Do not guess a code fix or start another CI merely to manufacture new accessible logs.

Production also requires the user-selected real model ID, acceptance currency and spend ceiling, a real total-token/price proof, installed production source/profile/authorization owner and controlled credential identity/generation/revocation with retention policy, reviewed HTTPS/auth adapter and separately authorized real provider acceptance. This slice explicitly rejects production; it is not real DeepSeek acceptance. Seven physical-device items and real foreign constructor/destructor/SQLite.close failures remain NOT_RUN.

PR86 and dependent I04 HOLD remain. PR90/Dart8 unchanged. No old task.db→HTTP→original-state reopen, rewrite, split, changed environment or indirect suite executed; old job117717160270 and old service-durable-owner-evidence-39127896088-1 downloads were never accessed. No .env/key reads, persistent provider credentials, real/paid model call, deployment, main/develop merge, force push or branch deletion.
