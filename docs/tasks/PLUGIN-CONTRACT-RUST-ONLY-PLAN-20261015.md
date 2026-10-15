# Rust-only read vertical slice: execution handoff

Status: planned / not run. The preceding Dart implementation target is stopped;
checkpoint `249a8205b259999d1ff88730366df7e7e860fd6d` is retained as a migration
oracle, not imported into the active Rust integration. This plan and
`docs/design/PLUGIN-CONTRACT-RUST-ONLY-SLICE-20261015.md` are a small native read
experiment, not M03/public API finalization.

## Ownership and start condition

- Plugin original owner: existing `experiments/redesign/plugin-contract-lab`
  source, tests and fixtures; bounded Rust declaration mappings and Catalog API.
- Original core writer: existing `experiments/redesign/core-agent-lab/core` only;
  generic port in the one Agent drive loop and generic controlled provider schema
  projection/decoding, retaining existing wrappers/regressions.
- Original host writer: proposed
  `experiments/redesign/rust-agent-host-lab/core` composition crate; native
  installed read handlers, authority/facts, original receipts, actual model
  payload admission and process lifetime.
- Original checker: a separately reviewed Rust-only normal CI gate. No Dart or
  Flutter executable is a runtime/build prerequisite of the native target.

Original core/host writers are not live in this thread. Parent must resume those
original owners or designate explicit file carve-outs before implementation.
A read-only reviewer does not become a product writer by implication. This
thread does not edit core files or create the host crate while those owners are
unresolved. No additional user kickoff permission is requested.

## First executable vertical slice

Two turns, one read: the native provider receives a bounded completed structured
call, the same core Agent loop requests native host admission, the host invokes a
Rust equipment read handler and stores its original receipt, the real Catalog
child accepts a host-selected schema-valid projection, and the next exact model
payload contains only that projection. The provider returns a synthetic answer.
Use only synthetic equipment e1/loan l1 data and a local scripted protocol fixture.
Capture exact outgoing payload bytes at the actual native provider transport
boundary, after final admission. No real model, credentials or user data.

The native host installs the handler through an opaque binding id. The Catalog
child is actually spawned from the built Rust binary; it does **not** execute the
business handler. Its current `invoke` response carries dispatch arguments; its
`accept_result` validates a reference to the host-owned receipt. This first slice
therefore proves **host-installed Rust read handlers plus a real contract child**.
It does not prove arbitrary plugin executable loading, sandboxed business code,
handler execution IPC, or the complete migration of research/inquiry storage and
business logic. Those remain explicit migration gaps.

### Batch A: common core port, with original core owner

1. Preserve the single `Agent::drive`; replace its concrete host dependency with
   a narrow port abstraction covering existing persist/control/dispatch/failure/
   answer roles and a dynamic registered-tool directory. HostPorts implements it.
2. Generic enabled native paths receive operation schemas/names from the host.
   They do not hardcode inquiry.object, research names, equipment names or
   fixture.record. Keep old wrappers as separate compatibility test oracles.
3. Reuse bounded JSON/SSE/transport and ProviderControl. Add generic native call
   history and schema projection through this existing provider implementation;
   do not fork another decoder or Agent loop.
4. Expose a final payload admission hook that sees the actual serialized model
   payload and covers all live read projections referenced by history/tool logs.
   Missing authority is refusal; no implicit affirmation from HostFacts::default.

TDD handoff: compile an explicit refusing interface and a target positive test;
actual behavior RED must be a precise unsupported/refusal assertion after the
core loop is reached. Compile errors/timeouts/targets not started do not qualify.

### Batch B: native host and plugin composition, with original host owner

1. New sibling host crate depends on core + plugin. Core never depends on plugin,
   avoiding a cycle because plugin currently imports core wire_json.
2. Start one actual bounded Catalog process. Register complete equipment metadata
   and one separately installed host binding. Registration and discover have zero
   handler calls and zero grants. Do not introduce a handler-execution IPC.
3. Native host prepares complete authority snapshots (availability, read/scope,
   binding/source/rule revisions, exact refs and versions), calls Catalog prepare,
   rechecks before Catalog invoke and native handler invocation, and records the
   one original result/identity in the native receipt owner.
4. Persist premark/source facts in native host storage before handler dispatch and
   postref facts before acceptance. Reuse private-directory/lock/bounded atomic
   file primitives for this experiment; separate versioned receipt/fact/task
   records and validate all loaded fields. Do not repurpose fixture write receipts
   or migrate the production database. A persisted denial/unknown fact cannot be
   cleared by plugin labels or a restart.
5. Send host-selected projection and owner receipt reference to Catalog accept
   with a fresh snapshot. Review actual selected values against classifications
   and model purpose. Persist the raw original receipt independently; never store
   a second authoritative projection receipt.
6. Immediately before actual next model send, recheck every live visible
   projection's source/read/binding/scope authority. Final synchronous admission
   after awaited checks is the linearization point. Revoke before it blocks the
   data send; already sent bytes cannot be revoked.
7. Close/cancel/EOF/deadline bounds apply to every owned child/thread/pipe. Failure
   after a real handler outcome preserves its original receipt. Restart retains
   facts/receipts but cannot reconstruct a live grant from model text.

### Batch C: declaration mappings and business-name independence, plugin owner

Files proposed only inside existing plugin-owned directories:

- `core/src/mappings.rs`: bounded Rust metadata mappers / constructors.
- `fixtures/research_read.json`, `fixtures/inquiry_read.json`: frozen native
  declaration subsets, with source provenance to original module declarations.
- `core/tests/mapping_contract.rs`: metadata-only mapping and admission tests.

Research/inquiry retain their native `type`/`id` input shapes. Equipment retains
`equipment_key` / `include_loans`. DATA and RELATION have explicit targets and
schema versions; operation input/output schema and view references are separate.
Unsupported ontology field kinds or unadmitted reference targets must produce an
explicit exclusion report or refusal, not a loose arbitrary JSON schema.
Declarative sensitivity is evidence for host review and cannot authorize access.

Map selected project/document and supplier/product subsets without executing Dart
or reading real storage. Register all three Rust declarations; each host-native
synthetic handler reads only its explicit scope. Repeat with seeded namespace,
operation, data/relation names and opaque binding ids changed consistently.
Changing fixture names requires no Agent/provider/host-policy switch edits.

## Native gate assertions

The existing 16 Rust Catalog tests remain their own regression suite. New native
case names/counts are to be fixed jointly with the core/host/checker owners before
running; they must not be misreported as the old 12 Dart matrix.

- Exact valid metadata publishes atomically; invalid final view or relation
  publishes nothing and reserves no binding/name. Register does not grant/read.
- Current filtered discovery plus generic provider projection exposes only
  authorized names and required DATA schema closure. Missing/unknown authority
  fields refuse, not default allow.
- Actual common Agent loop + native host handler + real Catalog child achieves
  the positive two-turn equipment read. Original receipt count is exactly one.
- Wrong argument/result schema, typed ref, schema version, object revision,
  receipt identity/owner, operation generation or scope refuses at its intended
  boundary. Each negative starts from a valid complete request and changes only
  the tested field; include the valid sibling positive.
- Handler count is zero without permission and before a denied pre-invoke revoke.
  Deterministic barriers after receipt/before accept and after projection/before
  actual send preserve the original receipt and produce zero data-bearing sends.
  Include a previous conversation turn's projection in the late-revoke scenario.
- Raw sensitive result/summary, failed handler content, malformed projection and
  toolLog/history cannot bypass selected-value classification/purpose review.
  Premark/postref facts persist on failure; forged clean/trusted labels do not
  clear them. Unknown classifications are reviewed rather than assumed safe.
- Cancel before dispatch executes zero; cancel after handler keeps the original
  receipt but publishes no model projection. Actual pending-ticket EOF and a new
  process reject the old ticket. Deadline/error paths clean up owned resources
  within explicit bounds, with no unbounded test wait.
- Restart requires fresh authority for every visible historical projection;
  persisted receipt/taint survives and is not an automatic grant.
- Research/inquiry/equipment and seeded rename pass the same generic native
  route. No Dart process, model credential, true external endpoint, Android,
  migration, DDL/write/CAS/hotload is part of this gate.

## Integration and evidence

Root alone imports/pushes. Cherry-pick this docs commit's diff, never merge the
whole author ancestry containing the paused Dart checkpoint. Preserve earlier
RED logs, test failures and checkpoints. Each implementation batch reports exact
source SHA, built binary SHA, compile evidence, actual executed target/case counts,
nonzero RED versus GREEN and planned/not-run coverage. Existing Rust component
security acceptance is complete; native Agent/host integration is not yet run.
