# Plugin public DATA admission closure

Owner: plugin public contract writer. Base:
`0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`. Scope is the existing experimental
`plugin-contract-lab` and this task document; no global schema/ABI/public freeze.

## Existing capability and bounded gap

The Rust Catalog already atomically registers DATA, RELATION, read operation and
view declarations, publishes only current-authority-filtered operations and their
schema closure, and supplies prepare/invoke/accept_result with one-shot tickets,
generation/current-snapshot checks and host-owned receipt identity checks.
Registration/discovery never installs a business handler or grants authority.
Research, inquiry and equipment metadata mapping constructors already exist.
No additional registry, provider or Agent loop is needed here.

The gap is foreign DATA admission closure. `host_data_admissions` currently
checks a referenced foreign type directly, but discovery walks all typed schema
references reachable from it. Admitting `equipment_loan/loan@1` alone therefore
implicitly publishes the referenced `equipment_loan/equipment@1` schema for a
consumer operation. The current Rust-only plan explicitly requires refusal of
unadmitted reference targets (`PLUGIN-CONTRACT-RUST-ONLY-PLAN-20261015.md`,
Batch C); the design calls for closed schema dependencies, not an implicit grant
from a plugin's reference annotation. Require explicit host admission of every
foreign target in the referenced closure, keeping local DATA available within its
own atomic bundle. This is metadata admission, not read or model-export authority.

## Test-first evidence

Test-only checkpoint `f65b3c1ee6133d441bdfa6bc280d720f0b44b2ad` adds
`foreign_data_admission_requires_the_referenced_schema_closure`. A valid consumer
operation declares only the foreign loan as its direct DATA dependency. Missing
loan admission, missing transitive equipment admission and equipment@2 in place
of equipment@1 must each refuse with `unresolved_data` and unchanged inspect
state. Repairing only the admission list must register, discover exactly the two
required schemas and retain zero executions/grants/receipts.

Run the behavior RED on the immutable test-only checkpoint:

```sh
cargo test --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml --test registration foreign_data_admission_requires_the_referenced_schema_closure -- --exact --nocapture
```

Local `git diff --check` passed. Local Cargo/Rust execution is NOT_RUN: no Cargo
toolchain is installed in this environment. Missing toolchain is not behavior
RED. Root alone pushes or triggers the existing remote gate. Actual remote
RED/GREEN evidence and the final implementation SHA will be appended when known.

## Limits

All data and handlers remain synthetic and trusted host builtins. Fixtures do not
establish executable third-party plugins, production storage or actual networking.
Typed scope/revision validation, purpose review, source facts and the one original
receipt remain with their existing owners. No real device, model, migration,
write/CAS/DDL/hotload or final M03 acceptance is claimed.
