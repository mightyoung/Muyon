> Latest held schema2/edited preparation slice: [SCHEMA2-REPORT.md](SCHEMA2-REPORT.md).
> Previous results below remain historical; no engine publication is enabled.

> Latest durable COPY batch: see [DURABLE-REPORT.md](DURABLE-REPORT.md).
> Earlier contract-only results and limitations below are historical.

# DOC-06/08 engine-neutral observations

`Binding` contains the shared immutable `documents::DocumentRef` (workspace/project,
document ID, canonical Revision, format), host-computed patch digest, original intent
and optional explicit rollback target Revision. The digest must cover the canonical
typed patch, target anchors, expected old values and invariants; the module does not
implement format patch schemas or compute an engine payload digest.

`Authority` is an alias of existing `contract::AuthorityBinding`, not another grant.
`HostFacts` carries current source Revision, live authority, active access, shared
operation permission intersection and shared capability matrix. It is never built
from model output/document contents/wire JSON. Default Unknown denies. There is no
production DocumentHost adapter and no default supported matrix.

Typed `Command`s: Inspect, Read, Propose, Preview, AwaitApply, ApplyCopy, Validate,
Commit, Export, OutcomeUnknown, RecoverApply, RecoverCommit, Cancel. All record or
validate host observations; none execute an engine or return executor permits.
Inspect/Read/Preview do not return document bytes or rendered previews. `Previewed`
means accepted lifecycle observation, not evidence that an actual UI was rendered.
AwaitApply records the original confirmed in-flight intent without dispatching it.
ApplyCopy requires a distinct immutable candidate bound to the entire transaction.
Validation binds that exact candidate/hash and explicitly checks reopen/container,
structure, semantics, render comparison, unsupported-feature preservation and formula
status. These supplied booleans are not implementations of format validators.

Commit accepts only a matching durable host receipt, candidate, old base Revision,
successful host CAS and exactly `previous_revision.next()` as the resulting Revision.
The shared checked increment rejects same/backward/skipped versions and overflow;
this also applies to original-intent recovery and new rollback transactions. Source revision conflict retains
the candidate. Unknown accepts only the matching original intent's query results;
ordinary apply/commit cannot replay it. A missing receipt leaves the state unresolved.
Cancellation records a request; a late durable original commit is still observable.
In-flight cancelled apply may recover its immutable candidate but cannot continue.
`rollback(next_binding)` constructs a New, unconfirmed transaction with new intent,
current committed base, same document/scope/format and an explicit different target.
It does not undo bytes or revive a consumed confirmation.

The host MUST persist an intent once, bind observations to actual source/candidate
bytes, atomically recheck permissions and CAS with publication, and query durable
original-intent history across crashes. An in-memory Transaction cannot enforce
cross-process duplicate exclusion or persist recovery by itself. No decoded grant,
read preflight, CAS boolean or enum name is authority to publish. Existing business
permission/DB implementations are untouched. No real Office editing, SDK, network,
model request or file-writing code is present here.
