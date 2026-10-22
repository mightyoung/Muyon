# Schema1->2 journal preservation: focused parent review repair

Base d50d3415ed3794b10b7277dd95d8faa5c7e1eafe, clean local checkout and matching remote confirmed before starting. No previous preservation patch was present. Own only group_runtime/store.rs initializer, dedicated group_runtime_bridge tests and this directory. No owner/lib/FFI/network/model/environment/permission changes.

Reproduce actual SQLite schema-version UPDATE triggers deleting a legacy pending row, rewriting an existing receipt, injecting a journal row, or injecting a new original-command binding. Fixture uses actual local committed/rejected/pending intent facts, then reconstructs the exact version1 table set by dropping only new bindings and restoring version1.

Capture the complete ordered legacy journal row set before migration writes; after the existing schema/version checks, compare all original column bytes/NULL values and require newly created bindings remain empty. Only reads then commit. This witness applies only when actually migrating1->2, so normal v2 initialization with real post-migration bindings remains usable. Any discrepancy returns Storage and drops the transaction, restoring version1, old journal/receipts and absence of the new table.

Keep raw RED logs for all four faults, fixed GREEN, normal legacy queries/no replay/idempotence, existing tail/recovery/whole core regressions, independent focused review and frozen hashes. Push this independent fix branch and verify full remoteSHA and main/develop unchanged. Prior301 results are historical, not proof of this new behavior.
