# Plugin contract slice 1 implementation plan

> Execute with superpowers:executing-plans, preserving the authorized original plugin owner. Root assigns independent review and is sole pusher. Do not replace the owner or ask again for startup permission. Interface review of the linked design is the next gate; no implementation precedes that review.

Design: [bounded registered reads](../design/PLUGIN-CONTRACT-SLICE1-20261015.md). Base: `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace`. Isolated clone `/tmp/Muyon-plugin-contract-slice1-20261015`; branch `task/plugin-contract-slice1-20261015`. Logs/cache/temp `/tmp`. This plan is a first slice, not M03 freeze.

## 1. Documentation and ownership gate

Commit only design and this plan with `[skip ci]`; hand fixed SHA to root for independent contract review. No source/API/workflow changes in that commit. The design's ownership table is exhaustive. Any additional shared file requires owner alignment first. Parent-approved AgentDispatch carve-out includes `_complete` and `_logEntry` only for port-owned model projections, plus external-source/read dispatch. No changes to Agent model loop, bootstrap defaults, UI or core-agent experiment.

Checkpoint: review covers protocol/schema/generation split, trusted source seam, raw result/summary isolation, real Agent routing, original receipt ownership, classification and final model gate. Resolve contract findings before writing stubs.

## 2. Compile stubs and assert behavior RED

After review create new crate `muyon-plugin-contract-lab` (binary of same name) at `experiments/redesign/plugin-contract-lab/core`. Keep public stubs type-correct and return explicit unsupported/rejected outcomes. Reuse existing bounded parser through the local path dependency; do not modify it. Add the 16 Rust cases below; first establish compile success separately. Add Dart interfaces/nullable injection and 12 tests with real Agent/ToolRegistry/fake gateway harness, with the bridge stub refusing the positive read. Existing legacy path stays untouched.

The two required RED targets are:

- Rust integration target `registration`, test `atomic_registration_publishes_only_valid_bundle`, assertion text `PLUGIN_SLICE_RED_RUST_ATOMIC_PUBLICATION`. A valid bundle must publish exactly one generation and expected contribution counts; stub returns unsupported, so this assertion fails after successful compilation.
- Dart file `test_plugin_contract/agent_read_port_test.dart`, test name `registered read reaches original receipt and reviewed model projection`, assertion reason `PLUGIN_SLICE_RED_DART_AGENT_READ`. Assert one original handler execution, receipt owner identity and sanitized model-visible result; stub refusal causes an assertion failure, not unresolved symbols.

CI owner runs each RED separately; workflow must genuinely fail on the assertion. Rust RED failure must not prevent Dart RED from being attempted in its own suite. Preserve compiling source commit, build logs and failing assertion logs outside Git. Do not accept missing executable/import, schema parse setup failure or Flutter setup failure as behavioral RED. Parent only requests push/normal CI after code is concrete.

## 3. Minimal Rust implementation GREEN

Implement schema/namespace/ref validation and canonical arguments first, then atomic registry publication and filtered discovery. Add prepared ticket state with one pending invocation per port; revision/generation/epoch checks; consume before callback. Accept results only for the exact pending owner receipt reference and strict projection schema; reject unsolicited/duplicate frames. Add cancel and EOF invalidation with deterministic tests (no sleeps).

Do not implement business handlers, grant creation, SQL, writes/CAS, migrations, restarts or a second execution ledger. Original ToolRegistry remains actual execution/receipt owner. Rust binding checks are necessary admission checks, not a substitute for live host policy.

## 4. Minimal Dart trusted seam GREEN

1. Add immutable resultSensitivity to ToolDescriptor and copy in HostToolRegistrar. Tests distinguish absent/unreviewed, declared none and trusted actual-value review. Preserve existing defaults.
2. Add host-owned source metadata lookup to ToolRegistry registration/inspection path; no metadata accepted from tool arguments. Preserve current receipt owner and identity.
3. Implement process transport, catalog mapping, read bridge, source policy and model projection in the five new files. Use a private host driver and an explicit absolute binary path passed from host/test; no model-controlled executable path.
4. Inject nullable PluginReadPort through PersonalAgent/AgentContext. Existing ToolSelectionStrategy injection intersects current registered eligible tools with permission-filtered Rust discovery. Port-enabled reads all route through the port; unavailable/unregistered reads refuse rather than falling back. Without port behavior remains unchanged.
5. AgentDispatch source marking uses host metadata on the port branch, preserves premark/post-ref HostAuthorizationFacts and original ToolRegistry invocation. Reference checks and result validation precede model projection. Use current live authority again at dispatch and model purpose review.
6. `_complete`/toolLog/citations use only host-validated ModelReadProjection for port-owned invocations. Static host errors handle denied/invalid paths. Raw summary/data/errors never enter model history/toolLog. The final existing HostModelAuthorization actual-byte and compatible-body gates still run.
7. Add declaration-derived research/inquiry narrow mappings and equipment-loan fixture, then seeded random rename. Fixtures contain synthetic data only; registration has data-access/grant counters at zero.

## 5. Fixed behavioral matrix

Each row is one named top-level test; parameterized adversarial values remain within that test. Expected full total: Rust 16; Dart 12. If implementation needs extra cases update the matrix/count honestly before reporting. At this documentation commit: 28 planned / 28 not_run / 0 passed.

| ID | Rust target/name | Observable assertion |
| --- | --- | --- |
| R01 | registration::atomic_registration_publishes_only_valid_bundle | Valid bundle publishes once; invalid last view/relation publishes nothing and generation unchanged. Required RED target. |
| R02 | registration::registration_neither_grants_nor_reads | Handler/read/grant counters zero, catalog addition alone cannot discover/invoke without authority. |
| R03 | registration::namespace_duplicates_and_versions_reject | Duplicate module/name and unsupported protocol/schema reject entire bundle; prior catalog unchanged. |
| R04 | registration::schema_subset_and_limits_fail_closed | Unknown keywords, duplicate keys, oversized/deep frames, invalid required/enum/number forms reject. |
| R05 | registration::relation_and_view_refs_must_resolve | Versioned DATA and relation field targets must resolve; view is reference-only and never executes. |
| R06 | registration::discovery_filters_current_authority | Denied/unavailable/out-of-scope operations absent; no token from discovery. |
| R07 | registration::declaration_labels_cannot_authorize | Forged grant/trusted/clean fields reject; sensitivity declarations do not add authority. |
| R08 | registration::renamed_bundle_is_semantically_equivalent | Seeded names do not affect schema/permission/ref behavior. |
| R09 | read_contract::prepared_bindings_are_exact | Canonical keys equivalent; arg/scope/ref revision/authority/generation/epoch changes reject. |
| R10 | read_contract::revoke_before_invoke_executes_zero | Current snapshot revoke rejects with no host callback. |
| R11 | read_contract::ticket_is_one_shot | Repeat invoke/result cannot dispatch or accept twice. |
| R12 | read_contract::receipt_reference_has_original_owner | Foreign invocation/tool/identity receipt references reject; valid pointer accepted, no receipt minted. |
| R13 | read_contract::invalid_projection_and_refs_reject | Missing/extra/type-invalid fields and foreign/stale/out-of-scope refs yield no accepted projection. |
| R14 | read_contract::cancel_before_dispatch_executes_zero | Cancellation invalidates prepared ticket; no callback. |
| R15 | read_contract::cancel_after_dispatch_accepts_no_projection | Late response cannot produce model projection; original owner outcome untouched. |
| R16 | read_contract::eof_and_concurrency_fail_closed | EOF invalidates epoch; second concurrent read gets busy; no replay on restart. |

| ID | Dart target/name | Observable assertion |
| --- | --- | --- |
| D01 | catalog_contract::registrar preserves sensitivity without granting | Descriptor immutable exact metadata, missing unreviewed; registration zero grants/data accesses. |
| D02 | catalog_contract::actual declarations map three distinct read contracts | Real research/inquiry declaration mapping plus equipment schema; native arguments preserved; view refs only. |
| D03 | catalog_contract::permission filtered catalog drives selection | Existing selection injection sees only registered currently eligible operations; stale directory cannot permit dispatch. |
| D04 | read_bridge::live revoke and scope changes prevent handler execution | Live host changes after prepare: handler count zero; no fallback. |
| D05 | read_bridge::owner receipt survives projection rejection | Original receipt identity/result retained, malformed result/foreign ref yields no ModelReadProjection. |
| D06 | read_bridge::cancel and process failure preserve owner semantics | Before dispatch zero executions; after dispatch no accepted projection; no duplicate receipt/replay. |
| D07 | agent_read_port::registered read reaches original receipt and reviewed model projection | Real Agent read dispatch calls original handler once; one original receipt; only valid projection reaches fake gateway. Required RED target. |
| D08 | agent_read_port::renamed third module retains source and purpose gates | Seeded rename follows same Agent path; trusted source premark/postrefs and final gate preserved without name switch. |
| D09 | agent_read_port::raw summary result and toolLog cannot leak | Success/invalidArguments raw poison strings absent from tool/user messages, next-turn toolLog and citations; schema/ref rejection yields zero data sends. |
| D10 | agent_read_port::plugin labels cannot clear source facts or classify values | Forged clean/none cannot erase existing ledger contamination; actual-value host deny/unreviewed yields zero data sends. |
| D11 | agent_read_port::final model payload review remains authoritative | Valid read/projection but denied final payload or compatible-body review yields zero model sends; assert actual reviewed bytes. |
| D12 | agent_read_port::no port preserves legacy and missing projection fails closed | Legacy no-port read unchanged; enabled unknown read or lost live projection refuses, never raw fallback. |

Tests must assert event order (premark before handler, receipt before projection, source/ref/classification before final review, review before gateway send), not merely final text. Counters and deterministic barriers replace sleeps. The fake gateway is local and uses no credentials. Static grep is supplementary; rename and ledger behavior are decisive.

## 6. CI handoff to checker

Checker owns workflow exclusively. Suggested workflow_dispatch suites `rust-red`, `dart-red`, `full`, operating on root-provided fixed commit. Exact crate/bin: `muyon-plugin-contract-lab`. Env `MUYON_PLUGIN_CONTRACT_BIN` is absolute path to `experiments/redesign/plugin-contract-lab/core/target/debug/muyon-plugin-contract-lab`. Rust is unavailable locally; normal CI is mandatory, not optional future validation.

Build before either RED suite:

```sh
cargo test --offline --locked --no-run --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml
cargo build --offline --locked --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml --bin muyon-plugin-contract-lab
```

Rust RED:

```sh
cargo test --offline --locked --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml --test registration atomic_registration_publishes_only_valid_bundle -- --exact --nocapture
```

Dart RED, working directory `apps/muyon`, binary env set by CI:

```sh
flutter test test_plugin_contract/agent_read_port_test.dart --plain-name 'registered read reaches original receipt and reviewed model projection' --reporter expanded
```

Expected RED: compile succeeds; selected test count 1, assertion failure carrying the corresponding marker; normal workflow conclusion failure. Rust and Dart RED are separate workflow runs/suites; do not use continue-on-error to report GREEN. Full GREEN:

```sh
cargo test --offline --locked --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml
flutter test test_plugin_contract/catalog_contract_test.dart test_plugin_contract/read_bridge_test.dart test_plugin_contract/agent_read_port_test.dart --reporter expanded
```

Dart commands run from `apps/muyon`; Rust command from repo root. Existing affected regressions also required: `test/tool_registry_test.dart`, `test/agent_dispatch_safety_verification_test.dart`, `test/assistant_authorization_facts_test.dart`, and relevant host registrar/module-contract tests located before code edits. Preserve existing assertions. Analyze changed Dart files with the repository's existing Flutter setup; do not generate/push unrelated lock/cache changes.

## 7. Finish and evidence

After new GREEN and affected regressions, stop implementation expansion. Hand root exact source SHA, diff scope, test counts and actual CI evidence; independent reviewer checks contract closure and no source/model leaks. Raw logs under `/tmp/rd-plugin-contract-slice1-20261015`, summaries only in Git. Parent alone pushes draft/review branches; no merge, grant change, deployment, model call, Android run, production data or historical migration. Any unavailable CI/test is a reported blocker rather than passed evidence.
