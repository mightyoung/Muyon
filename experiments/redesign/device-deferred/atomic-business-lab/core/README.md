# RD-P07 atomic synthetic supplier lab

Replaceable local experiment for RD-P07 Task 1. Formal M03 remains `blocked_contract`; this protocol and SQLite layout are not product contracts or authority. Inputs are the parent [contract](../CONTRACT.md), M02/D03a, and the unchanged `../../rust-domain` RD-P01 crate. Only synthetic Linux private temporary databases are supported by this evidence. P06 is closed and was not reverified.

## Build and verify without installations

```sh
export CARGO_HOME=/tmp/muyon-spike01-toolchain/cargo
export RUSTUP_HOME=/tmp/muyon-spike01-toolchain/rustup
export RUSTUP_TOOLCHAIN=1.99.0
/tmp/muyon-spike01-toolchain/cargo/bin/cargo build --offline --locked --manifest-path Cargo.toml
/tmp/muyon-spike01-toolchain/cargo/bin/cargo test --offline --locked --manifest-path Cargo.toml
python3 tests/process.py
python3 mutations.py --evidence-dir /tmp/rd-p07a-evidence-20261014/reviewer-mutations
```

Run these commands from this `core/` directory. `RD_P07_BIN` can select an independently built executable. `RD_P07_SQL_EVIDENCE=/tmp/private-evidence.jsonl` optionally records independent SQL queries/rows and subprocess requests/replies in external files. Mutations modify only `src/main.rs`, compile each inverse change into an external target, require an intended real assertion failure, restore source bytes after each attempt, and rebuild/rerun the complete suite against restored source. Use a separate evidence directory for each run to preserve failures.

The actual author toolchain was Rust 1.99.0 (`b940084d7`, x86_64 Linux). The executable links the exact already-installed `libsqlite3.so.0` runtime using a checked minimal C ABI wrapper, not a downloaded SQLite crate. Actual `/proc/self/maps` discovery during `init` reported:

- `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6`, SQLite **3.46.1**;
- SHA-256 `14c4418a06c5c2e30f5fb57bc8add93762236ae17898c6708984cf15e680ca71`;
- independent Python 3.12.14 stdlib SQLite **3.53.1**.

The Rust and Python SQLite runtime versions differ. These are actual loaded versions, not a diagnosis of historical SQLite CI failures. Initialization fails if runtime-path/hash discovery is unavailable. Cached `rustfmt` was unavailable; no component or package was installed.

## Trusted one-shot CLI

```sh
./target/debug/rd-p07-atomic --db /tmp/PRIVATE_DIRECTORY/fixture.sqlite --request '{"op":"init","domain":"synthetic-A","scope":"scope-A","supplier":"S1"}'
./target/debug/rd-p07-atomic --db /tmp/PRIVATE_DIRECTORY/fixture.sqlite --request '{"op":"commit","domain":"synthetic-A","scope":"scope-A","supplier":"S1","intent":"I1","operation":"supplier.name","raw_utf16":[32,65,102,116,101,114,32],"expected_revision":"1","plan":"P1","candidate":"C1"}'
```

The trusted harness owns an already-private directory, selects the physical path, and declares synthetic identities. CLI fields do not confer user/renderer permission. Each invocation is a new OS process. `--db` and `--request` are required, each once. Successful protocol replies are JSON with exit 0; parse/storage/unavailable errors use stderr and exit 2. A trusted `exit:STAGE` fault exits 86. A trusted `barrier:STAGE` fault flushes `BARRIER STAGE` to stdout and parks for external SIGKILL, so fault-mode stdout is not an ordinary JSON reply.

Requests are strict flat JSON objects. Unknown fields, duplicate keys, absent/wrongly typed fields, invalid u16 values, and noncanonical revisions are rejected before opening the database. No epoch, attempt, or transport field is accepted as a second intent identity.

| `op` | Exact fields besides `op` | Behavior |
| --- | --- | --- |
| `init` | `domain`, `scope`, `supplier` strings | Explicit synthetic fixture creation only; supplier must be `S1`. Refuses any existing path. Creates private file mode 0600 and S1/S2 at name Before, revision 1 with distinct untouched fields. |
| `read` | same three strings | Current supplier ID/name/revision only. |
| `preview` | complete binding below | Hypothetical normalized name/revision; no intent/effect/receipt write. |
| `commit` | complete binding below | Atomic pending claim then one guarded business transaction, or original committed replay/rejection/unknown/conflict. |
| `lookup` | complete binding below | Read-only verification of original intent/history/receipt. Missing/unverified receipt stays unknown. |

Complete binding fields are `domain`, `scope`, `supplier`, `intent`, `operation`, `raw_utf16`, `expected_revision`, `plan`, and `candidate`. All but `raw_utf16` are nonempty strings; raw is an array of exact UTF-16 u16 units (including isolated surrogates for actual Rust rejection). Revision is a positive canonical u64 decimal **string**, retained as SQLite TEXT. The sole business operation is `supplier.name`. Intent equality includes the full raw argument array, original revision, domain/source, scope, supplier, operation, plan, and candidate; request `op` only selects a read/preview/commit/lookup path.

RD-P01 handles raw ≤2000 units, XML validation before trim/NFC, nonempty and ≤200 codepoints, CAS preconditions, and overflow. The lab never duplicates the name algorithm or narrows values to signed SQLite INTEGER/REAL. It does not assert complete Dart/Rust Unicode equivalence; M04/M05/M03 remain dependencies.

## Physical transaction and original receipts

The explicit fixture format uses application_id `1380208695`, user_version 1, one meta row with domain and `rd-p07-local-v1`, and `suppliers`, `intents`, `history`, `receipts` tables. Opens check marker, column order/TEXT affinity/NOT NULL/primary-key constraints, and canonical physical supplier revisions, with no migration or source adoption. Synthetic labels are not authenticated store identity. Trusted private failure triggers are permitted; triggers that falsify the final effect are detected before commit.

`BEGIN IMMEDIATE` serializes the pending ownership claim. Existing binding is compared before replay; a committed intent must verify original history/receipt, and its original receipt is returned before current stale CAS is reconsidered. Changed valid binding conflicts. Missing committed receipt or bound pending intent stays unknown and never redispatches, even when independent SQL effect counts are zero. A proven validation/CAS rejection retains its binding/reason without a business receipt. A later fresh same-normalized-name intent increments revision and gets a separate physical receipt; the CLI's trusted-harness setting does not prove a real new user instruction.

After the durable pending transaction commits, a separate `BEGIN IMMEDIATE` contains all four applied facts: parameter-bound guarded supplier update with checked affected row count, history row, committed intent fact, and original receipt row. The adapter queries the actual effect after UPDATE and again checks the final complete supplier rows and bound intent/history/receipt after receipt insertion, before COMMIT. This catches actual triggers that modify the final name/revision/receipt/status and rolls the entire business transaction back, preserving the prior durable pending fact. Unrelated supplier fields/rows are also compared. Receipts contain original binding, binding SHA-256, source/domain, supplier, old/new names and canonical revisions; SHA-256 is integrity correlation, not an authority signature. The physical original receipt is independently verified against local committed history. Historical receipt and current supplier read are separate after later commits.

SQLite errors, trigger failures, and busy/COMMIT failures produce unavailable errors. Potentially dispatched pending work is reconciled through lookup and stays unknown without a verified receipt. The lab does not equate a storage error or lookup notFound with zero dispatch.

## Read-only and crash boundaries

Read/preview/lookup open using `SQLITE_OPEN_READONLY` (1), with no CREATE or URI flags, and use a read transaction for a consistent snapshot. Commit opens using READWRITE (2), without CREATE; only explicit init reserves a new file. Fixture initialization chooses DELETE journal; writers request synchronous FULL. A read-only open/query may be unable to recover a hot rollback journal: that is unavailable, with no fallback to a read/write connection. The suite generates a genuine spilled hot journal with Python, kills the writer, then observes all three read-only operations fail and the journal/database bytes remain unchanged. This narrow physical check does not promise universal byte/mtime invariance of SQLite bookkeeping. Commit may perform ordinary engine recovery on its authorized read/write connection. There are no migrations, backup restore, imported source substitution, or unknown retries.

Trusted `--fault exit:STAGE` and `--fault barrier:STAGE` support `pending`, `update`, `history`, `intent`, `receipt`, `commit`. Pending is durably committed before the business transaction; the four intermediate stages are inside that transaction; commit is after COMMIT and before JSON reply. SIGKILL cases use private databases and deterministic barriers. Real receipt insertion failure uses a Python-created RAISE(ABORT) trigger. These prove process-death atomicity for this installed runtime/local filesystem; disk/controller power-loss durability, production authority/retention/schema/backups, external-provider exactly-once, Android/Compose/Electron, and product entrypoints are outside the experiment.

Author evidence: **24 unique process methods**, **2 Rust unit tests**, **6 SQL-exit stages**, **6 SIGKILL stages**, **4 final-trigger consistency subcases**, and **5 compiling inverse mutation classes**. Counts are separate and not added into an invented product test total. Source restoration and full GREEN followed the final mutation run. The CAS inverse is caught by the final verifier as unavailable/pending instead of the required bound CAS rejection; it does not demonstrate a committed stale write. The duplicate inverse fails original replay through the unique constraint, not a second successful write. Other inverse classes catch missing shared atomicity, ignored pending binding, and forbidden pending redispatch.

Raw logs/query transcripts stay under `/tmp/rd-p07a-evidence-20261014/`, outside Git. `verification-evidence.json` records summaries and source hashes. Non-author review/C0, exact candidate regression CI, push and sole integration belong to Leader B; author GREEN does not satisfy those gates. Existing historical SQLite CI RED and platform NOT_RUN are unchanged.
