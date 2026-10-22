# Independent review — C contract and A source

Reviewer is read-only on product worktrees. No I04 operation, provider/HTTP/reopen sequence, model call or Android runtime was executed.

## C narrow contract freeze

Reviewed `/workspace/leaderb-store/docs/tasks/leaderb-store-readonly-20261018/CONTRACT.md`, SHA256 `f84ee42c540ce9a6b11347caa7def97d61f0b796992d708a9ac71d5b64768c4d`. Conditional review required and received: domain schema12 vs hosted inquiry schema3 distinction; immutable trusted callback/file/ancestor ownership; explicit byte/scalar bounds; fresh current consumption vs historical original receipt. Freeze accepted for a private Rust dependency slice only.

Source cross-checks: `supplier_core/store.dart` defines meta format `supplier-inquiry` / schema12 and supplier JSON row schema. `inquiry_plugin.dart` separately owns hosted ModuleSchema3 plus migration triggers. Frozen v1.3.2 handbook D01.1 selects supplier identity/name/revision. `HostScopeAuthority`, `ManagedConnection`, and `ScopeResolver` demonstrate why DB rows alone cannot reconstruct live authority. Mandatory host callback remains a seam until real Dart/native wiring is supplied. Existing `NativeSession` performs authority equality checks around registered dispatch and projection acceptance.

No implementation acceptance yet. Review must verify stable SQLite data_version and read transaction ordering, path/source incarnation checks, real dense schema fixture, original receipt identity, and current projection revocation. Domain reader limits do not redefine supplier normalization.

## A fixed source review

Source `136477f4fb8b3c84f64c3ad66f6d6f402c72ffbc` in `/workspace/leaderb-min26`. No source blocker found. App minSdk26 and lab minSdk26 agree with current V2 schema/validator/native linker/stubs/ELF selector/APK gate; shipping targetSDK remains Flutter-owned and lab targetSDK remains36. Existing V1 document/schema bytes are unchanged and historical evidence was not rewritten. New workflow checks checkout SHA and independently builds shipping APK, lab and native ABIs; those are build checks, not Android runtime acceptance. No UI/OCR source or permissions changed.

Independent commands at exact HEAD: `python3 -B -m unittest discover -s experiments/redesign/android-rust-bridge-lab/checks -p 'test_*.py'` exit0,71 tests pass; `git diff 136477f4^ 136477f4 --check` exit0; worktree clean before/after. Negative-fixture mismatch/exit diagnostics printed by tests are expected controls. V2 schema SHA256 `6a9c5168816de5188fa7ef15b8e9f00fc2b745278ef02206fac3806ab30f93c2` matches pinned verifier; V1 schema hash remains `1e47b50edc6e85e352e5d931e10c7a1ef18f0b4b85b112e17bf71664c4a1bece`.

Full Android CI39101615298 and generic CI39101615134 were pending at this source review; no full build success or device/runtime result is claimed.

## A superseding exact source e49be079

Reviewed source `e49be079eb6f3367df9b5c6d5eb1f29b74c989ae` after parent reported source supersession. Three-file followup adds dated diagnostic supersession, expands source manifest to V2 schema/doc/new workflow, and explicitly rejects format_version1. No new source blocker. Independent exact-HEAD rerun of the same71 Python tests exits0 (1.253s); followup diff check exits0; worktree clean. No prior136477f4 native/CI result is adopted for this SHA. Required CI39101690023 and generic39101690016 remain pending at this review update.

## A release-registry workflow correction

Source `3f3a2368648db5e9767f11adcae4548ac5da2527` supersedes e49be079 only in the workflow. Coordinator reports e49 AndroidCI39101690023 shipping compile failure: generated registry includes dev-only integration_test class absent from release classpath. Exact restored Flutter3.47.5 source confirms regeneratePlatformSpecificToolingIfApplicable returns without --pub, while release generation filters dev dependencies and Gradle release excludes them. Allowing the release command's pub step corrects that registry/classpath mismatch; postbuild git diff enforces unchanged workspace lock. No dependency upgrade, product behavior or targetSDK change. Independent current-SHA71 Python controls pass; source clean and diff check0. Full build at this source remains pending; prior source native successes or shipping failure are retained separately.

## A actual full-build terminal review

Read terminalJSON and full compressed raw logs for [required AndroidCI39102166352](https://github.com/mightyoung/Muyon/actions/runs/39102166352): completed/success at3f3a2368648db5e9767f11adcae4548ac5da2527, all four jobs success. Actual shipping releaseAPK built and lintRelease/ReceiptObserver check ran successfully. aapt2 reports minSdk26/targetSdk36 at exactSOURCE_SHA; APK SHA2566ed859f31c89479e2fb2f0a0c5a116278869c759b71e4a0d09d601c689676c49. Separate lab compilation without optional native inputs and fresh native API26 links/stub checks for arm64-v8a/x86_64 passed at this source. Combined optional-native lab APK packaging remains NOT_RUN. APK was not retained as an artifact; its logged hash/badging are build evidence, not a delivered installable binary. No installed Android8/device/Service/store migration acceptance follows. Prior e49 release-registry failure and superseded source evidence remain preserved. Generic CI39102166368 is still pending at this update.
