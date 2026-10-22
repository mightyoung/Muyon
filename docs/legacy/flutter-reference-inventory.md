# Flutter retirement prerequisite: references, not retirement

Fixed old tree: `214b4031deb38ca7dfd35ee86396089eb48157d5`. Its immutable tree
and selected source/oracle blob hashes are recorded in `flutter-source-manifest.json`.
Git history is the full reference; this file is not a packaged runnable archive.
The current active Flutter entrypoints and coverage floors are unchanged.
PR101 legacy CI39822618984 remains FAILED (2395<2401); no historical pass is invented.

| Existing entry | Dependency and status in this slice |
| --- | --- |
| `.github/workflows/ci.yml` | Flutter Linux analyze/eight suites/coverage unchanged. Laya now separate unconditional job. |
| `verify.yml` | Flutter macOS/manual verification unchanged. Laya now separate unconditional Linux job; not desktop acceptance. |
| `ui-preview.yml` | Flutter test/static-web package; unchanged, still historical retirement work pending. |
| `reg4c-verification.yml` | Flutter/Dart format and behavioral inverse runners; unchanged. |
| `android-min26.yml` | Old Flutter shipping APK/observer/API26 build; unchanged. |
| `package-artifacts.yml` | Old Flutter Android/macOS/Windows packager; manual/storage/redistribution conditions unchanged. |
| `scripts/{ci,verify,doctor}.sh` | Still old Flutter entrypoints; doctor may inspect model configuration/contact `/models`, so never run it implicitly during this slice. |
| `scripts/package_artifacts/` | Fixed historical tooling source referenced; no dispatch or new product packaging. |
| Rust `supplier_store.rs` | Only two include_str paths now use byte-identical frozen schema12 test fixtures. Every original Rust assertion remains. |
| Supplier normalization differential | Original PRODUCT01e56cc2 / FIXTURE8c599551 pins, oracle source and dependency fingerprints retained; not executed/rewritten here. 32 cases do not prove global Unicode equivalence. |
| Host inverse Dart runner | Script pinned at214; referenced `apps/muyon/test_host/core_agent_host_inverse_oracles_test.dart` is NOT tracked there. Manifest records the missing entrypoint/NOT_RUN; closure must be recovered/reviewed before declaring historical reproduction complete. |
| Plugin Dart evidence reader | Historical parser, not a production runtime dependency; unchanged. |

The schema fixture manifest names original source path/blob/SHA256/size. The offline
checker detects missing/altered fixture bytes without Flutter or Git history.
`test_retirement_prerequisites.py` additionally compares actual bytes with fixed Git
objects (requires those local history objects; it never fetches them automatically).
The source declaration says what was frozen; it is not an authority or a user DB.

All three production Rust path dependencies under `experiments/redesign/` remain:
`rust-agent-host-lab/core`, `core-agent-lab/core`, `web-search-lab/core`. No API/test
module removal, model/license/native/package gate change, publication enablement,
user-file deletion, old data migration, or default-entry switch occurs here.
Electron production and full inquiry/quote replacement remain unready. Future
Office engine/service work is Rust; Laya's existing Python offline tests are not
an Office engine replacement.

Laya runner preserves the four original tests in order, stops with a failing exit
on any failure, runs from `scripts/laya`, and needs no Flutter job success or setup.
Tests use synthetic fixtures (including temporary fake env files), never user keys.
No branch-protection/settings change is made. New job must actually run to establish
hosted evidence; local green is not a GitHub check result or a retrofit of old skips.
