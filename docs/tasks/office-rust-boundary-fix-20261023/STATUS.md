> Historical pre-restoration checkpoint. Superseded by REPORT.md after explicit toolchain authorization and real execution.

# Validation and preserved work

Source HEAD remains 796cdfe7cb3d79d630056239724af78128094fee. Draft file crates/muyon-office/tests/boundaries.rs and this task's docs/evidence are untracked and intentionally preserved. No production source delta, commit or push.

| Command (from /workspace/office-rust-boundary-fix) | Actual exit | Outcome |
| --- | --- | --- |
| cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-office --test boundaries | 127 | NOT_RUN: cargo absent |
| cargo test --offline --locked --workspace --all-targets --manifest-path crates/Cargo.toml | 127 | NOT_RUN: cargo absent |
| cargo clippy --offline --locked --workspace --all-targets --manifest-path crates/Cargo.toml -- -D warnings | 127 | NOT_RUN: cargo absent |
| cargo build --offline --locked --manifest-path crates/Cargo.toml -p muyon-android-ffi --features bindings | 127 | NOT_RUN: cargo absent; generation/cmp not attempted without native build |
| bash apps/muyon_android/gradlew --offline --no-daemon --console=plain -p apps/muyon_android :app:compileDebugKotlin :app:compileDebugUnitTestKotlin :app:lintDebug | 2 | NOT_RUN: existing Gradle8.13 absent |
| python3 -B -m unittest discover -s apps/muyon_android/checks -p 'test_*.py' | 0 | PASS17 existing checker tests; no Android build/device assertion |

Raw outputs are in evidence/. Existing source-only findings: sheet_text collects S:t inside S:rPh, unlike shared_strings; DOCX expected/replacement are not byte-limited, escape/splice allocates before output budget checks; public rewrite_part validates only final compressed size; Package::open counts expanded bytes but not each max_part before later read_part. XLSX replacement and direct rewrite use the same unchecked splice/rewrite path. Text extraction also constructs paragraphs/cell values/shared string content before applying some text limits. These require a unified bounded approach rather than compressed-size-only approval; no untested patch is offered as fixed.

The original synthetic regression draft covers both requested paths but has not been compiled or run. Further multi-run/section and numeric-input budget cases remain necessary when the Rust toolchain is available. A static independent check is requested separately; it cannot substitute for executed regression, immutable-source final review or device validation.
