# PIP-07 supplier version map

Scope: source-backed contract mapping only. F2 Dart source
`3f1be180bb009a91e659c113ba5b1916e5360332` plus separately inspected LeaderB
store source `fdc9aea120925229aa592c3551efab9b3f67a825` (unmerged candidate).
The store owner selected supplier name; no parallel Equipment reader is added.

| Layer | Existing identity / source | Compatibility and rejection responsibility |
|---|---|---|
| Catalog request protocol | `protocol_version:1`, `plugin-contract-lab/core/src/lib.rs` | Exact supported envelope and closed keys; not a business DB version |
| Native business DATA / operation | `inquiry/supplier@1`, `inquiry/supplier_name@1`, binding `host-supplier-name-read`; store candidate `supplier_name_contract.json` | Closed supplier name subset and typed references; native version1 does not certify all supplier fields or relations |
| Supplier domain storage | `supplier-inquiry`, `schemaVersion=12`, `packages/supplier_core/lib/src/store.dart` | Domain format/history1–12 retained. Current native reader requires exact meta schema12 and table/storage types; incompatible versions refuse rather than migrate/create |
| Host module storage | `InquiryPlugin.schema`, ModuleSchema3, `apps/muyon/lib/app/inquiry_plugin.dart` | Separate migration IDs1–3 and definition digests, plus StorageManager structure/history validation. Domain12 is insufficient to certify hosted schema3 |
| Foundation / auxiliary storage | WorkspaceRepository host schema; separate inquiry hub/jobs schemas | Not supplier domain or native DATA version; no blanket compatibility inferred from supplier read success |
| Object/source revision | supplier row integer `version`, native ref decimal `revision`; current host authority revisions plus reader connection `PRAGMA data_version` | Source/current-authority checks are independent of schema identity. Same row revision with changed source stamp is not assumed fresh |
| Projection | Existing closed supplier/name projection accepted with original receipt_ref in local native facade | No independent explicit projection version field currently certified; do not invent one or treat operation version as DB migration version. Service summary ABI still excludes business name/projection |
| Catalog generation / run build | Catalog publication generation, Catalog session epoch; Service build/session identity | Runtime invalidation/evidence only; neither substitutes for definition digest, source revision or protocol version |

## Original migration inputs to retain

`ModuleSchema` requires version>=1, nonempty definitionDigest, and one migration
per version. Migration versions are ordered/contiguous, IDs unique, digests
nonempty, and the final digest equals schema.definitionDigest.

Inquiry hosted migration declarations are:

| Version | Migration ID | Input to existing `_digest` function |
|---|---|---|
| 1 | `inquiry-host-v1` | `inquiry-host-v1:domain12` |
| 2 | `inquiry-host-v2-change-log` | `inquiry-host-v2:domain12:change-log` |
| 3 | `inquiry-host-v3-change-log-contact-product` | `inquiry-host-v3:domain12:change-log-contact-product` |

These are digest inputs, not literal persisted digest values. Keep the existing
function/encoding and migration callbacks; no Rust-schema-derived replacement
or new digest is written. `StorageManager._open` rejects newer versions,
same-version definition drift, structure drift, mismatched historical
ID/digest or invalid applied_at, gaps/incomplete migrations, and foreign-key violations. Existing
transaction and compatibility repair policy remain with the migration owner.
`storage_manager_test.dart` already includes the same-version drift/preserve-data
case; this session did not execute Dart tests and does not reopen that task.

## Negative cases and remaining compatibility gaps

| Case | Existing source/test evidence | Status in this slice |
|---|---|---|
| Foreign DATA and nested foreign dependency without host admission | F2 `registration::foreign_data_admission_requires_the_referenced_schema_closure` | Re-executed in original22-test suite; explicit closure required, no grant inferred |
| Typed cross-module ref or stale revision in result | F2 read_contract invalid_projection_and_refs_reject / prepared bindings | Re-executed in original suite; no authority downgrade |
| Unknown protocol / unsupported schema field / missing binding | Original suite plus independent probe | Re-executed; fail closed |
| Same host schema version, different definitionDigest | Dart StorageManager and its existing test | Implemented source; Dart execution NOT_RUN here |
| Unknown domain DB version / malformed source / revision/authority drift | LeaderB supplier_store.rs and named supplier_store tests at store SHA | Source-inspected only; test execution belongs to LeaderB, not credited here |
| Hosted schema3 with correct domain12 but altered triggers/history | Store CONTRACT explicitly excludes certification | OPEN to original migration owner; domain-subset reader acceptance cannot close it |
| Supplier merged_into/contact/product relations, arbitrary payload extras | Real domain ontology supports more than name; native selected subset has no relations | Outside selected name contract, not migrated or implicitly exposed; any expanded contract needs scoped refs and mapping |
| Real production authority and Dart/native bridge | Mandatory trusted callback exists; real adapter remains required by store contract | OPEN to LeaderB; test callback is not production authority |
| Independent projection evolution or old receipt compatibility | No separately certified projection version mapping | OPEN with result/projection owner; do not rename old receipts or rewrite outcomes |

No actual user database was opened, modified, migrated or recreated. This map
keeps PIP-07 separate from PIP-08; neither production migration nor device
compatibility is declared complete.
