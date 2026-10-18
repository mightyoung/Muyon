# PIP parallel task path ownership — fixed 2026-10-18

LeaderB remains sole integrator. This is a path ownership release only, not acceptance or integration of the new DeepSeek/PIP work. New PIP task: 01a14d94-610e-7725-9f34-84d3ff3990c7. PIP registry/lifecycle work stays on its own branch and does not duplicate the real store/authority/projection slice.

## Released / not written by B or C

- `experiments/redesign/plugin-contract-lab/core/src/lib.rs`
- `experiments/redesign/plugin-contract-lab/core/src/schema.rs`
- all other existing `experiments/redesign/plugin-contract-lab/**` source paths
- `experiments/redesign/rust-agent-host-lab/core/src/service_runtime.rs`
- all other existing host runtime source except the module declaration path below

PIP may inspect/use these paths on its independent branch. Changes to Catalog/NativeSession/read authority or projection semantics require explicit integration review against the fixed store candidate; source ownership release does not waive compatibility.

## C reserved paths

Branch `task/leaderb-store-readonly-20261018`, fixed source `fdc9aea120925229aa592c3551efab9b3f67a825`:

- `experiments/redesign/rust-agent-host-lab/core/src/lib.rs` — only two-line Linux module declaration; avoid concurrent changes to this file until LeaderB integrates/reconciles
- `experiments/redesign/rust-agent-host-lab/core/src/supplier_store.rs`
- `experiments/redesign/rust-agent-host-lab/core/src/supplier_sqlite.rs`
- `experiments/redesign/rust-agent-host-lab/core/src/supplier_name_contract.json`
- `experiments/redesign/rust-agent-host-lab/core/tests/supplier_store.rs`
- `.github/workflows/leaderb-store-readonly.yml`
- `docs/tasks/leaderb-store-readonly-20261018/**`

No Cargo manifest/lock or original runtime file changed. New module reuses existing Catalog/NativeSession APIs. Source is frozen; only separate evidence writers remain while terminal logs are collected. Scoped C CI39102209762 is completed/success at the exact fixed SHA; production Dart authority bridge/Android SQLite/Service/UI consumer remain absent.

## B reserved paths

Branch `task/leaderb-sqlite-investigation-20261018`, fixed source `190477fe0e5008d473508e45d2d835ddd5e0c09c`:

- `apps/muyon/test/le06_recovery_independent_test.dart`
- `apps/muyon/test/support/isolated_flutter_project.dart`
- `docs/tasks/leaderb-sqlite-native-assets-20261018/**`

No production Dart/Rust source or existing CI changed. Full B CI is pending; do not inherit its eventual result into a new PIP SHA.

A current Android/minAPI branch is separate (`3f3a2368648db5e9767f11adcae4548ac5da2527`); shared Gradle/Android packaging and its CI remain LeaderB-owned, with UI/OCR external ownership unchanged.

I04 remains DENIED_BEFORE_EXECUTION/BLOCKED. Nothing here permits its original legacy-provider→HTTP→reopen action, any retry/reroute, PR86/dependent combination or main/develop integration.
