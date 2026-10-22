# Rust Office phonetic and output-boundary fixes

Base SHA796cdfe7cb3d79d630056239724af78128094fee; independent task branch task/office-rust-boundary-fix-20261023. The exact source snapshot tested and independently reviewed is identified by evidence/review-source.sha256 and SOURCE-ENVIRONMENT.json. A later source commit SHA is recorded in the final handoff. Only muyon-office Rust source, original synthetic Rust tests and this independent task's evidence change. Rust/UniFFI/Android APIs, authentication/publication gates and the narrow supported edit formats are unchanged. Claude's branch and d16 ProductService integration are untouched. No Python Office implementation was added. Original worktrees are preserved.

## Resulting behavior

Inline spreadsheet cells now exclude Spreadsheet namespace rPh pronunciation text, scoped independently per cell. Shared/inline rich-text, default/prefixed namespaces, foreign names, empty phonetic elements and adjacent cells have real ZIP/XML regression coverage.

DOCX/XLSX edit inputs are byte-bounded before validation scans. DOCX measures exact XML escape expansion and checked splice length before escape/splice allocations. Both edit routes and public rewrite share new-target part and expanded-package checks, using actual decompressed original member sizes. Directory-named entries with payload are also counted; a trailing slash cannot conceal expansion. The output text/XML/section budgets use the reader's same replacement view before compression, including shared strings and their references, other sections and empty-text placeholders. Appends are checked before growth. Untouched members still use raw_copy_file. A seekable bounded archive buffer checks logical growth before reserve/write, including raw copies and central directory. Failed edits return no receipt/candidate and leave source unchanged; subsequent valid edits remain usable.

These are logical byte/structure budgets, not allocator/RSS guarantees. Existing opaque non-target members retain their existing read_part max_part semantics; this fix does not newly reject every such source part at Package::open. All edited target parts must fit max_part. Low-level rewrite changed_range remains a caller declaration, not an authorization or semantic proof. No drawing/visual validation/recalculation or broader editing formats are claimed. ZipWriter emits its fixed finalize FileTooLarge diagnostic on the expected archive rejection path; raw logs retain it. The failed candidate is not returned.

## Actual validation and preserved failures

Environment for Rust commands:

```
. /workspace/office-rust-boundary-fix-tools/env.sh
# PATH -> task-local official Rust1.93.1
# CARGO_HOME -> task-owned cache, CARGO_TARGET_DIR -> target-fixed
# RUSTFLAGS=-Lnative=/workspace/office-rust-boundary-fix-tools/native-links
```

The final independent source snapshot uses a distinct target-review; original baseline regressions use distinct target-red. This avoids reuse of artifacts between same-package worktrees.

| Command / check | Actual result |
| --- | --- |
| baseline cargo test --offline --locked --manifest-path /workspace/office-rust-boundary-red/crates/Cargo.toml -p muyon-office --test boundaries | exit101, 12 actual regression failures, 0 compile/setup errors; regression-complete-red.log |
| cargo test --offline --locked --workspace --all-targets --manifest-path crates/Cargo.toml | exit0, 601 passed /0failed /0ignored, 33 result groups; workspace-final.log |
| cargo clippy --offline --locked --workspace --all-targets --manifest-path crates/Cargo.toml -- -D warnings | exit0; clippy-final.log |
| cargo build --offline --locked --manifest-path crates/Cargo.toml -p muyon-android-ffi --features bindings | exit0; bindgen-final-build.log |
| uniffi-bindgen generate --library task-target/debug/libmuyon_android_product.so --language kotlin --config muyon-android-ffi/uniffi.android.toml --out-dir task-generated (cwd crates) | exit0; bindgen-final-generation.log |
| cmp freshly generated Kotlin vs checked-in muyon_android_product.kt | exit0, byte-identical; binding-cmp.log and built-artifacts.sha256 |
| python3 -B -m unittest discover -s apps/muyon_android/checks -p 'test_*.py' | exit0, 17 existing checker tests; android-checkers.log (checks only, no Python engine) |
| Gradle8.13 --version with task GRADLE_USER_HOME | exit0 on existing JRE21.0.12.1; gradle-version.log |
| restored Gradle --offline --no-daemon --console=plain -p apps/muyon_android :app:compileDebugKotlin :app:compileDebugUnitTestKotlin :app:lintDebug | exit1 before compilation: fresh cache lacks com.android.application8.11.1; android-restored-gradle.log |
| git diff --check; reviewed four-file hash recheck | exit0 |

Independent reviewer ran office boundaries12+fidelity12, full workspace601 (36 groups including empty doctests), strict workspace/all-target Clippy, and post-run hashes: PASS. Full actual commands, original outputs and report are under evidence/independent-final/. Review found no unresolved Important within this source snapshot. The reviewer did not independently run baseline RED or bindgen; those are author evidence.

Historical NOT_RUN127/2 outputs remain in evidence rather than being replaced with invented success. Further preserved intermediate outcomes: first workspace link failed because the existing OS SQLite library had no developer linker alias; a temporary task-local alias now points to the installed package's identical .so. The first additional XLSX test setup used a max_part too small for its workbook/rels, so a new original padded synthetic worksheet isolates the target-part limit; corrected baseline then really fails. office-shared-target-stale.log records artifact reuse from the baseline when two worktrees initially shared a target directory; final RED/fixed/review targets are isolated and fresh results supersede it. First bindgen invocation from repository root failed cargo metadata before generation; rerunning from the CI-specified crates directory succeeded. No failure is classified as a behavioral RED unless assertions actually ran on original source.

## Toolchain recovery provenance

User explicitly authorized task-directory official-tool restoration. Rust channel1.93.1 TOML was fetched from static.rust-lang.org and checked against its official .sha256; all four component archives (rustc/cargo/std/Clippy) matched that manifest. Versions: rustc1.93.1(01f6ddf75), cargo1.93.1(083ac5135), Clippy0.1.93. Component URL/hash records, manifest hash, installation commands/exits and versions are in evidence/toolchain-*. No sudo, global install, persistent credentials or security setting changes. Source artifacts are official Apache/MIT distributions; no new interactive legal acceptance occurred.

Gradle8.13 was fetched through the official services.gradle.org distribution endpoint and matches the repository-pinned SHA25620f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78. It is extracted only under /workspace/office-rust-boundary-fix-tools; no wrapper/global caches changed. Host SQLite3.46.1-7+deb13u1 is the existing Debian package, reused by task-local native-links/libsqlite3.so pointing to /usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6, with hash retained. No SQLite installation or library replacement.

## Android validation status

Android compilation/lint/device validation are NOT_RUN. The offline build actually stopped first at uncached AGP8.11.1. No APK/current-page/device result is claimed. SDK components are not installed and JDK17 is not restored; Gradle launcher validation used the existing JRE21, not CI JDK parity.

Further SDK installation/use requires acceptance of the [official Android SDK License Agreement](https://developer.android.com/studio/terms), whose section2 requires agreement before SDK use. Proposed future action: interactively review/accept required SDK licenses through official sdkmanager, then install the CI-pinned platform android-36, build-tools35.0.0, NDK28.2.13676358 and CMake3.22.1. The parent supplied the user’s prior explicit acceptance of this exact Google SDK agreement; that acceptance is authorized for this project’s cloud SDK installation and checks. No additional confirmation is required for it. Minimal JDK17/SDK preparation is now in progress; no SDK installation success or Android compilation is asserted yet. Other newly encountered agreements still require reporting. The final handoff records actual completion or precise blockers. No paid/model/search calls, deployment, branch deletion, main/develop merge, PR creation or user-computer changes occurred. Source fix is fully Rust-tested/reviewed; broader Android/device gate remains separate and explicitly incomplete.
