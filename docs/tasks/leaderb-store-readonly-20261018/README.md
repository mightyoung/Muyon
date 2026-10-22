# Supplier-name private read dependency

The Linux Rust host now has a usable local consumer facade, `supplier_store::SupplierReader`. It reads a synthetic standalone SQLite copy using the production domain12 table shape, performs the registered `inquiry/supplier_name@1` operation, persists the existing original ToolRegistry receipt, and returns the accepted `{supplier, name}` projection alongside `receipt_ref`. This is actual SQLite business-data reading rather than receipt observation alone.

This is a **Linux-only private dependency slice**, gated with `target_os="linux"`. The existing Android dependency does not link Linux `libsqlite3.so.0`. It is not an App/Service cutover: Android SQLite loading/platform adapter, the production Dart ScopeResolver/current-policy bridge, host schema3 migrations and actual Binder/JNI/UI consumption remain unimplemented. No real user database migration is demonstrated. It does not enable writes, OCR, a model or networking, or widen Service current/lookup summary ABI/M03.

## Trusted consumer API

```rust,no_run
use std::{path::Path, rc::Rc};
use muyon_rust_agent_host_lab::{AuthoritySource, supplier_store::{SupplierReader, SupplierReadResult}};

// Called by trusted host bootstrap, never constructed from a UI JSON request.
fn read_selected_supplier(
    current_host: Rc<dyn AuthoritySource>,
    standalone_copy: &Path,
    fresh_receipt_root: &Path,
    supplier_id: &str,
) -> Result<SupplierReadResult, String> {
    let reader = SupplierReader::install(
        standalone_copy, fresh_receipt_root, supplier_id, current_host,
    )?;
    reader.read_current(supplier_id)
}
```

Keep the installed reader alive for subsequent `read_current(id)` calls. Each call rereads current SQLite values and authorizes the registered operation again, creating a fresh receipt child directory under its protected receipt root. Old projection/receipt objects remain historical values; a UI must call `read_current` to label a name current and clear its current display on any error. Returned `receipt_ref` is the original identity already present in that session's `native.db`, not a new observer receipt. No caller-supplied path, SQL, authority snapshot, allow flag, or arbitrary type is accepted by `read_current`.

The host MUST install a real `AuthoritySource` delegating to the existing ScopeResolver, HostScopeAuthority and current host policy/revision state. It must fail on pending/revoking/unavailable authority, maintain source-owner/incarnation/data-version stamps, and return only the selected inquiry/supplier@1 reference. Foundation assistant_grants has model/write/outbound grants, not a read grant; module_grants is not object authorization. This crate cannot recreate the missing ephemeral authority from SQLite. Mutable trusted callbacks in tests demonstrate the boundary and are not production authorization evidence. The wrapper permanently retains that callback object, forces model_allowed=false, and rejects SQLite data_version changes without a changed host source stamp. A legitimate production update in the tests changes row version7→8 and host reference/source stamp together.

Installation requires a fresh receipt root. Reinstalling/recovery is not implemented, and this facade does not reopen a previous runtime. Unknown schema, unavailable/malformed/deleted/stale data or authority errors are returned as errors, without a fallback name. Successful historical receipts do not establish current values.

## Storage contract and limits

`CONTRACT.md` is the independently reviewed initial freeze (SHA256 f84ee42c540ce9a6b11347caa7def97d61f0b796992d708a9ac71d5b64768c4d). Domain format is supplier-inquiry/schema12; hosted inquiry ModuleSchema3 is a distinct migration contract and is not certified here. The synthetic fixture uses the actual meta/supplier DDL and dense eight-field supplier payload; other domain tables, indexes, host change-log triggers and host schema metadata are outside this reader's verified subset.

The connection uses SQLite READONLY without CREATE/URI interpretation. The private C ABI seam owns handles and bounded statements, permits at most64 returned rows and65536 bytes per cell, and waits at most250ms on busy locks. Queries and paths are fixed by trusted Rust; business source bytes are asserted unchanged. Receipt state is written separately. SQLite diagnostics are fixed codes rather than exposing raw sqlite3_errmsg/schema/path content.

The source payload cap is65536 UTF-8 bytes; the existing parser enforces32 container levels and32768 nodes. Supplier JSON must have exactly the eight persisted supplier fields; only name is projected, and unused values are not included in receipt raw content. Name has defensive caps4096 UTF-8 bytes/2000 Unicode scalar values, without normalization. These are reader safety bounds, not a replacement for the existing Supplier domain validation (which normalizes name with its own200-character limit). IDs have128 UTF-8 byte cap. Reading does not normalize or modify persisted values.

The host must freeze a trusted standalone copy's namespace during installation/consumption. The adapter snapshots and rechecks regular file/no-symlink ancestry dev/ino/uid/mode, and a persistent connection's data_version participates in current source identity. Static replacement, mode changes, symlink ancestry, concurrent commits during callbacks and row revision drift are rejected. stat/open/stat does not prove race-proof namespace binding under adversarial swap-and-restore, and live/hostile namespace support is explicitly absent. This limitation is a blocker to production live-store use, not a claim about all replacement races. No user database was opened or changed.

## Reproduction and evidence

Run the explicit safe target only:

```sh
cargo test --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --locked --offline --test supplier_store -- --nocapture
```

The test prints `BUSINESS_READ_EVIDENCE` with actual accepted synthetic name/ref and original receipt identity. It also verifies that identity exists in the durable receipt file and the SQLite bytes did not change. Python3/system SQLite is used only to create/modify synthetic fixtures; the adapter performs actual reads through native SQLite C ABI. No provider, HTTP, original-state reopen, model or real external endpoint is exercised.

I04 remains DENIED_BEFORE_EXECUTION/BLOCKED; PR86 and dependent integration remain held. This test target does not execute that action. Broad legacy runtime suites are intentionally not selected; no inherited CI is cited as this source's validation. Exact source/test evidence is recorded separately after committing.
