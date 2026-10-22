# Rust-only pivot: plugin owner's bounded handoff

2026-10-15. Direction: stop new Dart implementation. This is a reviewable next-slice
proposal, not a frozen public interface or M03 completion.

## Saved state and evidence

- Author clone `/tmp/Muyon-plugin-contract-slice1-20261015`, original branch
  `task/plugin-contract-slice1-20261015`, clean after checkpoint.
- Dart migration-oracle checkpoint:
  `249a8205b259999d1ff88730366df7e7e860fd6d`. Fourteen files preserved; no new Dart
  work after the stop instruction. Root retains its own local archive and will
  not import this checkpoint into the active Rust combination.
- That checkpoint preserves catalog mapping, bounded child transport, host
  snapshot/receipt/projection/source-fact logic, registrar sensitivity copying,
  Agent dispatch/model-admission seams and synthetic tests. These are design and
  differential oracles, **not** an accepted Dart runtime implementation. Last
  frontend-only compilation, `bridge-third-frontend.log`, reports error count 0;
  no post-checkpoint runtime success is claimed.
- Original Rust final fix: `281a1f376cacd3460f44d6e8f3c9e75bad266c0c`, following
  `a0bf6f6c59826cc25bd35f156ddbe84726792f81`, test commits
  `5011cd74248b42154ecaf7ac27103e7f7141d400` and
  `c0ca798860285478999c8922392cd8f9beae00d1`.
- Parent supplied normal CI 38702004129 on root `8a2d...`: Rust compile/build PASS,
  16 integration cases (8+8), no skips, unit/doc 0, exit 0/full_green. Log:
  `envelope-fix-full.log`; independent scoped rereview 2 SPEC/QUALITY PASS.
  Whole old workflow fails on the now-cancelled Dart stub stage. This is a Rust
  component result, not a Rust-only native end-to-end result.
- D12 diagnostic was mislocated initially: actual log `d12-diagnostic-r2-full.log`
  stack points to `agent_read_port_test.dart:191`, the enabled-port success
  assertion, after the no-port success assertion passed. The no-port task payload
  is succeeded/completed, error null, original handler/receipt succeeded. No
  legacy/default-policy fix was needed or made.

## Existing Rust source that should be reused

The following citations use the full fixed baseline SHA, not a moving worktree.
All paths begin `experiments/redesign/core-agent-lab/core/src/`.

| Existing component | Exact fixed source | Reuse and real limit |
|---|---|---|
| One common Agent drive loop | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/agent.rs:191` | `run_with_provider` and `run_with_ports` share `drive`; keep counters, cancellation checkpoints and interrupted-state persistence. The port type is concrete HostPorts at lines 198–204, and the exposed tool list hardcodes inquiry.object at line 218. A generic port seam needs the original core owner. Do not fork this loop. |
| Provider interface | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/model.rs:16` | Reuse Provider/ProviderControl and HostTool structured arguments. Default ScriptedProvider is fixture.record-specific; it is not a general plugin provider. |
| Existing Host adapter boundaries | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/host_session.rs:93` | HostAuthorizer.prepare, HostToolPort.invoke, HostPorts dispatch/journal/control are useful separation points. Existing concrete callback transport remains an oracle; it is not the future native authority. |
| Existing host specialization | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/host_session.rs:43` | HostStart requires inquiry.object; schema at 61 is type/id-specific; projection at 119 requires inquiry; provider at 273 requires inquiry.object. Do not promote these shapes to public plugin contracts. |
| Existing receipt-aware dispatch | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/host_session.rs:326` | Preserve ordering: prepare, control check, pending journal, invocation, original receipt identity, model-safe history, journal. Generalize the value boundary through registered schemas, not another business-name branch. |
| Bounded wire decoder/transport | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/wire_sse.rs:19` and `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/wire_provider.rs:58` | Reuse UTF-8/SSE completion, byte/time/control budgets and child handling. Decoder lines 50/56 and encoder lines 28–34 currently accept fixture.record only. Generic schema/name mapping belongs to the existing core/provider owner, not a second decoder. |
| Persistence primitives | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/store.rs:6` and `:33` | Reuse private directory checks, locking, bounded read and atomic fsync/rename. These are experimental file primitives, not a claim of product database parity. EffectStore/FixtureTool at 57–62 are fixture-write semantics, not native business read receipts. |
| Existing policy vocabulary | `16df5d9a34cfb8fb6d56d1f6b753a800889a6ace:experiments/redesign/core-agent-lab/core/src/policy.rs:11` | Mode/facts/decision tests are useful oracles. HostFacts::default (line 16) sets affirmative hard/scope/classification facts; **do not** use that default as a native read authority snapshot. Catalog authority requires complete explicit host fields and denies omissions. |

## Minimum ownership adjustment

Keep the original plugin writer and original core writer. No new author or
parallel writer in a shared directory.

1. **Plugin owner (this agent):** retain sole ownership of
   `experiments/redesign/plugin-contract-lab/core/{src,tests}` and
   `experiments/redesign/plugin-contract-lab/fixtures`. Proposed additions inside
   that existing crate are `src/mappings.rs` (Rust declaration mapping for
   synthetic research/inquiry/equipment) and tests for those mappings. Any typed
   Catalog admission API stays local here. The executable dispatch adapter belongs
   to the composition host below, not this metadata crate. No second Agent loop,
   provider decoder, generic framework or persistence subsystem here.
2. **Original core owner:** keep all
   `experiments/redesign/core-agent-lab/core` ownership. Needed narrow seam: make
   the common drive loop consume a host port abstraction with its existing
   persist/control/dispatch/failure/answer duties and a registered-tool directory;
   remove the business-name decision from the enabled native path. Exact Rust
   trait spelling/signature is the core owner's implementation choice. Add a
   final model-payload admission callback in the existing provider path, not a new
   sender. Existing host callback specialization may remain an isolated oracle.
3. **Native host authority/persistence owner:** assign explicitly to the existing
   core/host owner (or one named carve-out owner) before edits. It owns the single
   raw read receipt store, source-fact ledger, revisions, purpose review and
   live-snapshot producer. The composition adapter consumes Catalog and core driver ports; plugin owner never writes
   grants, source-clearing flags or a competing receipt. Required location can
   be a new sibling `experiments/redesign/rust-agent-host-lab/core` crate,
   importing both core-agent-lab and plugin-contract-lab. Core must not import
   plugin-contract-lab: the plugin crate already imports core wire_json. This
   composition boundary avoids a dependency cycle. Existing host owner owns
   runtime_ports, plugin_process, model_gateway, authority, store and read_registry
   responsibilities (files may initially be combined). The first native slice
   executes host-installed Rust handlers and invokes the real plugin child for
   metadata/ticket admission; it does not yet support arbitrary plugin executable
   code or a new business-handler IPC protocol. No product migration is proposed.
4. **CI owner:** original checker owns the Rust-only gate. It must compile/run
   actual Rust native Agent + native host + plugin registration, not invoke
   Flutter/Dart executables. Existing Rust 16 cases remain separate regression
   evidence. Dart source/tests are optional offline comparison material only.

This proposal needs a small owner-to-owner interface alignment, not another
public M03 freeze. New native plugin/composition implementation waits for that small owner seam
to be fixed; the completed Rust security corrections require no further expansion.

## Native data flow and the exact gap to fill

- Host registers complete DATA/RELATION/operation/view metadata into the existing
  Catalog. It installs a host-only binding-id-to-handler table separately.
  Registration/discovery never executes a handler and never grants permission.
- Host permission/scope/source service emits a complete current snapshot. Catalog
  discovers only authorized operations and their closed schema dependencies.
  The provider projects those schemas, using reversible registered names; neither
  Agent nor provider matches research/inquiry/equipment names.
- The same Agent loop receives a completed structured tool call. Native read port
  canonicalizes via Catalog and prepares against current authority/generation and
  a host-issued invocation/receipt identity. Invoke rechecks before the handler.
- Native host stores the original handler outcome exactly once under that
  invocation. The plugin Catalog accepts only its owner reference plus a strict
  projected value. Source facts are marked before invocation and after actual
  returned refs, including on handler/projection failure. A plugin's labels may
  increase required review; they cannot clear facts or declare itself safe.
- Projection validation checks exact DATA target/schema version, object revision,
  current scope and all result/ref/schema constraints. Host purpose/classification
  review sees actual selected values and descriptor/ontology classifications;
  absence is unreviewed. No raw summary, result, tool log or history fallback.
- Immediately before actual model send, native host rechecks current read/source/
  binding authority for every still-visible projection in the payload/history.
  The final synchronous admission point follows all awaited policy work. Revoke
  before it blocks the data send; already sent bytes cannot be retracted.
- On restart, raw receipt and taint survive, but missing live projection authority
  refuses model export. An old receipt is evidence of a past outcome, not a new
  grant. Cancellation/EOF/deadline clears pending tokens, preserves any original
  receipt, and bounds owned resource cleanup.

The new work is the **native authority/receipt/model-admission producer and generic
core port**. Existing Catalog already supplies registry/schema/current-snapshot
comparison and one-shot admission; it must not impersonate these missing owners.

## Bounded next acceptance (not run)

Use pure synthetic Rust data, a local scripted model fixture through the reused
provider protocol, and no actual model credentials/network/data migration.

1. Existing 16 Catalog cases stay green. Invalid last-row registration publishes
   nothing; registration grants/executes nothing; omitted authority exposes none.
2. Actual common Agent loop runs research and inquiry native declaration mappings,
   equipment native key/include_loans shape and a seeded fully renamed variant;
   zero business-name edits to Agent/provider/host authorization dispatch.
3. Native host owns exactly one raw receipt. Only validated projection reaches
   final payload/history/tool log; wrong result/ref/version/scope produces zero
   data sends and preserves the raw receipt.
4. Deterministic revoke barriers before invoke, after raw receipt/before result
   acceptance, and after projection/before send. Last barrier includes an older
   history projection, not only the latest call. No handler before authorization;
   no data send after late revocation.
5. Handler and projection failures retain premark/postref contamination; forged
   clean/trusted/none metadata cannot erase it. Unknown classification/purpose
   requires the host decision and cannot default allow.
6. Actual restart/EOF/cancel/deadline tests verify pending-token invalidation,
   bounded process/thread resources and original receipt ownership. Native
   persistence atomicity/failure assertions use existing store primitives.

Write/CAS, DDL, hot loading, full ontology/IDL coverage, product historical data
migration and final public interface freezing stay deferred.
