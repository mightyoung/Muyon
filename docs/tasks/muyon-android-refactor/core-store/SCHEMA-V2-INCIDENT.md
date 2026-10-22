# API26 development-store schema mismatch — 2026-10-20

## Actual failure and read-only evidence

The third product API26 instrumentation run (`/private/tmp/muyon-product-api26-third.log`) executed 7 tests: 6 passed, 1 failed. The real PDF path passed. The actual Android DEFLATE host froze the archive and sealed 11 records, but confirming its ResearchImport returned `unknown`, no receipt. No receipt/tail assertion was relaxed.

The parent exported only this synthetic fixture store for read-only examination: `/private/tmp/muyon-product-api26-fixture.sqlite`. Actual metadata was schema_version **1**, workspace `local-workspace`, **18** tables, missing **research_import_members**. There was one original pending intent (`intent:236917…`). Its project had zero research entries, zero research sources and zero published blob references, with **6 pinned uploads**. File SHA-256 remained `9927b11f3f4e7bb099c40dc11f60762d3b7c527d1b789519e24a5eae9d1c9ee9` before and after the `mode=ro` examination.

Cause: early development candidates had kept DB version 1 while the complete required table set evolved. The old open_existing checked only the version marker/workspace, so a previously initialized v1 store without the later import-tail table was accepted. Actual import SQL could not insert its member proof, the business transaction rolled back, and the durable original intent correctly remained unknown. The issue was schema identity/admission, not the DEFLATE decoder or an incorrect import algorithm guard.

## Reproduction and RED → GREEN

An added actual-P05 Rust case reproduces the domain shape: 11 projects/selecting maximum UUID, 11 distinct paper id/rev/title records, 3 separate identical newline-only logs, an actual method-8 raw-DEFLATE ZIP, a new source at expected revision 0 and records []. The ZIP uses valid final stored DEFLATE blocks to avoid a new compression dependency; it is not a claim to run Android's inflater. This test was already **GREEN on complete schema** before the schema fix and remains GREEN. An initial test type-inference compile diagnostic was fixed and is not counted as RED.

The real behavioral RED was two store-admission tests, run against the original open guard:

```
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test business schema_ -- --nocapture
```

Compilation succeeded, exit **101**, **2 failed**:

- `old_schema_v1_missing_tail_table_is_refused_without_changing_pending_identity`: the incomplete v1 store was accepted instead of InvalidVersion.
- `current_schema_label_does_not_authorize_a_missing_required_table_or_column`: a current-version marker with the required table missing was accepted.

After the production fix, the identical command exits **0**, **2 passed, 0 ignored**. The second test also executes its renamed-required-column case. The first verifies the original pending intent/command/binding, meta v1 and absence of the missing table remain unchanged: no create, migrate, delete or replay takes place.

## Fix and fresh checks

Store version is now **2**. Protocol and business versions remain **1**. initialize uses one shared list of 19 table DDL statements. open_existing checks version/workspace, then compares every required sqlite_master table definition to that exact initial DDL, including required columns/constraints. Semantically similar externally rewritten or partial schemas are not silently accepted. No automatic CREATE/ALTER/migration path was added to open_existing.

```
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test business --test research --test contract --test blobs
```

Exit **0**: business **14 passed**, research **16 passed**, contract **10 passed**, blobs **8 passed**, zero failures/ignored. Existing rollback, unknown, CAS and receipt checks remain active. Clippy/fmt results are included in the final completion handoff.

The parent's Android namespace, DB filename and UI preferences are explicitly versioned to v2 so a user creates a new v2 namespace. The old v1 test DB and unknown original identity are preserved; this lane did not clear, migrate or resend them. A new Android run is required before claiming the v2 installed candidate passes the failing product test.
