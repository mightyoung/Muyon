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

## Local Rust execution after root supplied the shared toolchain

Root installed and authorized the shared Rust 1.99.0 toolchain at
`/tmp/muyon-tools/cargo/bin`. This supersedes the earlier local NOT_RUN state;
the earlier toolchain absence was never counted as RED.

Both commands below used `CARGO_HOME=/tmp/muyon-tools/cargo`,
`RUSTUP_HOME=/tmp/muyon-tools/rustup`,
`CARGO_TARGET_DIR=/tmp/muyon-build/plugin` and the shared Cargo PATH prefix.
No toolchain was installed by this owner, and no CI workflow was changed or run.

- RED: the exact single-test command above, with `-j2 --offline` added, ran at
  `1d445ef339ead2d5f595bbfb97c444bdf81ef8f8` (only documentation added after
  test-only `f65b3c1`). Compilation succeeded; exit 101, 1 failed / 8 filtered.
  The behavior assertion was `expected unresolved_data, got
  {"generation":2,"ok":true}`. Thus the otherwise-valid consumer actually
  published with missing transitive admission.
- Implementation: `fc728271f9056f706a62e61036443f74080dff58` changes only
  `core/src/lib.rs`: the existing admitted-DATA lookup now traverses typed schema
  dependencies using a visited set, resolving every member through the same
  local-or-explicit-host-admission rule. It terminates on cycles and completes
  before any registry publication. No public symbol, message field or error code
  is added.
- GREEN: `cargo test -j2 --offline --manifest-path
  experiments/redesign/plugin-contract-lab/core/Cargo.toml`, exit 0: 22 tests
  passed (mapping 5, read 8, registration 9), zero failures/skips; unit/doc tests
  each contain zero cases. Existing inquiry self-reference mappings and the real
  bounded Catalog subprocess EOF/protocol tests also pass in this run.
- Python: `python3 -m unittest discover -s
  experiments/redesign/plugin-contract-lab/checks -p 'test_*.py'`, exit 0,
  7 passed. `git diff --check` passed.
- Built Catalog executable SHA-256:
  `cbf7fe75c83455cab0d8ff37b997da9895cfe9cf9505f3172143aee741fefc54`.
  The scoped target directory occupied 158 MiB.

Rust emitted two existing `suspicious_runtime_symbol_definitions` warnings for
the core dependency's `host_session.rs:132` C `read`/`write` signatures. This
owner did not alter that separately owned source. They do not fail these tests.
Independent fixed-SHA review, remote CI and integration are still NOT_RUN for
this slice and remain root-owned. No native host/Android/model integration
result is inferred from these component tests.

## Limits

All data and handlers remain synthetic and trusted host builtins. Fixtures do not
establish executable third-party plugins, production storage or actual networking.
Typed scope/revision validation, purpose review, source facts and the one original
receipt remain with their existing owners. No real device, model, migration,
write/CAS/DDL/hotload or final M03 acceptance is claimed.
