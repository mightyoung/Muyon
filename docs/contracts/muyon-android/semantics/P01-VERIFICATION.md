# P01 Rust contract verification

Worktree: `/private/tmp/muyon-android-refactor-20261020`, branch `codex/muyon-android-refactor`, initial integration base `cebc6876`. No business/device acceptance is claimed.

Implemented: real typed Rust strict JSON decoding, version/operation whitelist, lossless decimal revisions, raw supplier normalization and field constraints, project/paper/import/blob bounds, exact raw/opaque import metadata binding, read-lease/archive metadata shape, plan/retry digest and receipt/status invariants. Schema documents the same bounded wire; it does not execute security checks.

Executed on 2026-10-20:

```
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test contract
```

Exit 0: **10 passed, 0 failed, 0 ignored**. Tests cover CT01–CT04's Rust contract assertions: raw UTF-16/XML/NFC/BOM/scalar limits; eight supplier fields and forbidden merge; numeric ordering and large canonical revisions; mandatory project/title/attachment with 30 MiB PDF cap; opaque imported fields and original raw JSON equality; full retry identity versus changed scope/parameters/grant/epoch; strict recursive duplicate/unknown/version rejection; canonical key order and complete create/delete/restore receipt vectors; unknown/notFound versus cancelled/committed states; immutable snapshot/lease/member bounds and traversal denial.

```
rustfmt --edition 2021 --check crates/muyon-core/src/contract.rs crates/muyon-core/tests/contract.rs
git diff --check -- crates/muyon-core/src/contract.rs crates/muyon-core/tests/contract.rs docs/contracts/muyon-android
```

Both exit 0. Schema JSON and synthetic lifecycle digests also parsed/computed independently with Python stdlib. Initial compile found sha2 0.11 digest Array does not implement LowerHex; fixed by explicit per-byte lowercase hex encoding, then reran the actual Rust tests.

Open proof obligations: Kotlin execution and exact generated UniFFI bindings; trusted runtime grant issuance/expiry/revocation and SQL commit/cancel linearization; physical original receipts; actual file snapshot/ZIP/CRC reader; Android UI/Service/device workflows. A deserialized AuthorityBinding/ReadLease is a reference to trusted persisted state, never proof of authority. P01's Rust tests do not complete those integration obligations or full cross-platform M03.
