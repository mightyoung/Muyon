# Independent migration-preservation review — 2026-10-22

Branch: `task/mig20-group-migration-preservation-fix-20261022`. Base: `d50d3415ed3794b10b7277dd95d8faa5c7e1eafe`. Scope is ONLY the current initializer preservation diff and its tests; no reassessment or expansion into unrelated owners, dispatch or older branch assurances. Reviewer wrote only this task's reports/evidence and standalone /tmp harnesses. No production/native test edits, network, lib/FFI/owner operations or user files.

## Result

No remaining important defect found in this focused diff. The four supplied schema-version UPDATE trigger cases are independently reproduced against exact base source and prevented by current source, with real SQLite rollback. Existing-group legacy pending recovery and no-replay checks also pass.

## Fixed base/current comparison

Extracted old store verbatim with `git show d50d3415ed3794b10b7277dd95d8faa5c7e1eafe:crates/muyon-core/src/group_runtime/store.rs` into `/tmp/mig20-migration-preservation-review/base-store.rs`, SHA256 `91ac111c514385b04d2e4fe75c5bdbb74dd2a06dae0a2a499b963854d9fed9ad`. The standalone base/current targets use the same test assertions and current surrounding modules, differing only in the store source path. Copies of exact base source, both harnesses and manifest are saved in evidence.

- `evidence/independent-base-5-RED.log`: EXIT101, **1 passed / 4 failed**. The normal control passes; deleting pending history, rewriting receipt, injecting journal row, and injecting binding all incorrectly return Ok in d50d. The failed output includes real before/after rows. Original RED preserved.
- `evidence/independent-current-5-GREEN.log`: EXIT0, **5/5 pass**. Each fault returns Storage; the journal equals its entire original set, schema stays version1, and the newly created bindings table is absent after rollback. The normal control proves committed/rejected legacy reads, missing-group/no-command Unknown without fabricated identity, no group creation, and v2 reinitialization with a real later binding.

Reproduction uses the environment named in PLAN and `cargo test --offline --manifest-path /tmp/mig20-migration-preservation-review/Cargo.toml --test base migration_preservation_ -- --nocapture` (expected failure); replace `base` with `current` for GREEN.

## Additional independent controls

`evidence/independent-current-extra-4-GREEN.log`: EXIT0, **4/4 pass**. These are extra /tmp-only test functions, not additional native-suite tests:

1. Change a legacy pending SQL NULL receipt to the literal text `null`: detected and rolled back, preserving the NULL distinction.
2. Append one space to committed receipt JSON: detected and rolled back, proving raw persisted string comparison rather than semantic JSON equality.
3. Rename a pending intent while keeping row count unchanged: detected and rolled back, proving complete identity/set comparison rather than count checking.
4. Create an actual durable pending Configure in an existing group by failing the local group effect, reconstruct exact v1 schema, and migrate. Owner/admin repeated reads report PendingOriginal with null receipt and current_group_management identity; member is refused. Journal, business grants, groups, runs, nodes and events remain byte-for-byte unchanged across migration, queries, and v2 reinitialization. New bindings remain empty; no replay or fabricated original command occurs.

Source for the first three: `evidence/independent-extra-controls.rs`. Existing-group control: `evidence/independent-existing-group-pending-control.rs`. Complete current harness including all four: `evidence/independent-current-with-extra-controls.rs`.

## Source reasoning and regression limits

The intended legacy witness is captured only on an actual v1->v2 path, before the CREATE TABLE and schema UPDATE writes, as all seven journal columns ordered by unique intent_id. Values are compared as exact Option<String> rows, including raw receipt contents and NULL. After existing exact DDL/version verification, the complete current journal must match and the newly created bindings table must contain no row. A difference returns Storage before commit; transaction drop restores original journal/version and removes the new table. No writes intervene between final reads and commit.

The v2 path leaves the migration witness absent and accepts existing genuine bindings; it does not incorrectly require them to be empty. No other production function changed in this diff.

Independent native regression run: bridge **53/53**, store **65/65** pass (`evidence/independent-native-regression.log`). Bridge53 consists of the prior48 plus this patch's **five** new native test functions; source-imported tests remain included. Prior301/full-core numbers are not treated as new coverage or independent verification of this patch. Parent-reported full-core306 and fixed-document composition executions are not claimed as this reviewer's own executions. `git diff --check` also passed.

## Frozen hashes

- store.rs: `0b1b7ec30e749bf224d907570cc7c851b18411852346c2aa4a1bf60e7e9e53ed`
- group_runtime_bridge.rs native tests: `b44ebbfd89f744cc4fcc9791729179b4b2f396379647ca0048329424bf97303a`

All three group_runtime sources and both test hashes are in `evidence/independent-final-source-sha256.txt`; current store/test match the parent freeze. No production changes occurred during this review. No denied, pending or uncertain action; no remaining review blocker.
