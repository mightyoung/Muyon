# RD-P05A actual synthetic Rust core process

Unpublished protocol-0 laboratory backend. Source serde definitions in `src/main.rs` own the lab wire. `Request`/domain/seed reject unknown fields, explicit-null optional fields, enum/type/range/version errors. Identity labels are exact nonempty <=128 UTF-8 bytes; they are never trimmed/normalized/truncated. Revisions and seq are canonical u64 decimal strings (record revision >0). Invalid shape replies have empty untrusted ID/epoch and no data. NDJSON input frames and encoded output are capped at 32768 bytes excluding newline; unterminated EOF executes nothing.

Reproduce using installed caches, no download:

```sh
export CARGO_HOME=/tmp/muyon-spike01-toolchain/cargo
export RUSTUP_HOME=/tmp/muyon-spike01-toolchain/rustup
export CARGO_TARGET_DIR=/tmp/rd-p05-core-target
/tmp/muyon-spike01-toolchain/cargo/bin/cargo +1.99.0 build --offline --locked --manifest-path experiments/redesign/device-deferred/core-port-lab/core/Cargo.toml
/tmp/muyon-spike01-toolchain/cargo/bin/cargo +1.99.0 test --offline --locked --manifest-path experiments/redesign/device-deferred/core-port-lab/core/Cargo.toml
python3 experiments/redesign/device-deferred/core-port-lab/core/tests/process.py
python3 experiments/redesign/device-deferred/core-port-lab/core/mutations.py /workspace/reports/rd-p05a-core-20261014
python3 experiments/redesign/device-deferred/core-port-lab/core/tests/process.py
```

Start fixed executable `/tmp/rd-p05-core-target/debug/rd-p05-core --seed <trusted fixture absolute path>`. The only startup arguments are `--seed path`. No stdout banner; each newline request gets one reply. Standard seed and lost-reply seed are sibling `../fixtures/seed.json` / `seed-lost-reply.json`. Trusted fault `precommit_fail_once` may also be injected by startup synthetic fixture; requests cannot inject faults, reseed, supply receipts or reset private ledger. Tests may select a separately built binary via `RD_P05_CORE_BINARY`; this variable is test-only and no renderer receives arbitrary path authority. `RD_P05_EVIDENCE_DIR` selects the test harness's own external evidence directory (default writer report path); reviewers must set it to avoid overwriting author evidence.

Private in-memory rows, registered plans, business intents and ledger execute actual code:

1. preview calls unchanged RD-P01 read/edit candidate with full raw UTF-16. A candidate is not an effect.
2. commit first replays exact original intent/business/plan receipt or conflicts on reuse; otherwise rechecks registered immutable plan and current CAS through RD-P01.
3. cloned rows/RD-P02 reducer/ledger are staged, actual event received and checkpoint committed; receipt is generated from result, then all staged business state swapped at once. A precommit fault discards staged changes. This is memory atomicity, not a DB transaction/fsync/crash proof.
4. lost-reply fault applies the effect first, retains ledger and unknown, and returns unknown with all effect data null. lookup never calls commit, verifies private ledger through RD-P02 reconcile, and recovers original receipt without another event/revision.
5. reconnect delegates to RD-P02, preserving effects/unknown and changing only presentation epoch. Lookup can return an old verified receipt with current snapshot and stale display admission; it never applies receipt state over current rows. Snapshot and receipt are independent axes.

Fingerprints SHA256-bind fixed store/scope/action, raw original business command including object/intent/revision, and plan ID; request ID/epoch are excluded. Comparing complete stored original Business plus plan rejects altered raw/object/revision/intent reuse. New explicit synthetic intent with the same normalized name still increments once. This does not authenticate a real user instruction, grant or capability.

If final encoded reply exceeds budget, return `unknown/reply_limit` with the same valid request/epoch and null snapshot/plan/receipt. This does not mean no effect. Verified lookup first omits an oversized snapshot so a compact receipt can recover independently; it never skips identity/ledger validation. Large-seed test proves commit effect→unknown→receipt-only lookup→duplicate command with original receipt/seq unchanged.

24 actual process tests, four semantic inverse mutations (replay/CAS/lookup dispatch/old-receipt projection), and original source restoration are reported in verification-evidence.json. Original RED 16 tests had 12 assertion failures and 4 passes; protocol strengthening had 2 assertion failures; output budget and receipt-only recovery each had separate real assertion failures before fixes. Raw logs stay outside Git.

Lab-only seed controls, in-memory effects, replaceable serde representation and deterministic local IDs are not production authority, durable identity or M03 freeze. Process restart resets this private laboratory seed; cross-process persistence/recovery and real store are NOT_RUN. Android load/Compose/Electron runtime NOT_RUN. M03 blocked_contract. Real model/user data/device/install/new terms/account/security/payment/deployment are outside scope.
