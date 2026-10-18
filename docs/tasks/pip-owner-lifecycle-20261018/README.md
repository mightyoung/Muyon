# PIP-05/06: bounded Catalog owner lifecycle

Parent authorized continuation from audit record
`05d224f4b4fb31b3e015ea88cdaa7a14b03978b8`. Ownership verified by fetching
`docs/leaderb-next-20261018` at full
`52906b50db1825c165ac237a7f7a21efdc5a0bbf`, then reading
`docs/tasks/leaderb-next-20261018/PIP-PATH-OWNERSHIP.md`. This supersedes the
earlier audit's pending path-clearance blocker for plugin-contract-lab only.
LeaderB remains sole integrator. All rust-agent-host-lab paths (including
service_runtime.rs), store/authority/projection, Android/UI/OCR and migrations
are excluded by the parent's narrower assignment and were not edited.

## Implemented behavior

The existing Catalog still validates and atomically publishes a bundle. It now
retains a bounded owner record of its exact DATA/operation/binding keys,
relation/view counts and foreign dependencies at that same publication point.
No second registry, dependency, provider framework, Node/Cordis or wire command
is added. The original 22 Catalog tests remain unchanged.

The trusted Rust API optionally enrolls a managed bundle and returns an opaque
OwnerLease tied to that Catalog instance, host-assigned epoch and publication
generation. A plugin cannot choose/reconstruct it through JSON. Clones share an
epoch; a stale disposer returns Released without running cleanup, including
after a same-name replacement. A lease from another Catalog is rejected.
Generation/epoch are runtime identities, not schema/database versions.

Managed dispatch uses the existing authority, one-shot ticket and generation
checks and retains an opaque WorkLease before returning dispatch to the host.
Wire invoke cannot bypass this tracking for managed bundles. Existing wire
registration/dispatch remain available unchanged for legacy enrollment; no
existing host code is silently switched into the new lifecycle.

Stop rejects while a dependent bundle remains registered (including a legacy
consumer with no lease), without partial mutation. Shut down in reverse
dependency order. Otherwise stop fences discover/prepare/dispatch and same-name
reenrollment, invalidates that bundle's tickets, advances global generation and
sets cooperative cancellation flags on its work. New foreign declarations cannot
admit a stopping provider. A second stop is idempotent. As with existing register,
generation change conservatively invalidates all previously prepared tickets.

Draining state reports tracked in-flight work. Cancel, protocol close, successful
accept_result or dropping a work handle do not claim handler quiescence/durable
settlement. The trusted host must retain the work handle and call settle_work
only after its handler is actually quiescent; its synchronous callback must
persist final/unknown evidence under the original host receipt identity. A
callback error/panic leaves work tracked. A repeated successful settlement does
not replay persistence or settle a later epoch. Outstanding work is bounded at
128; quota rejection preserves the pending ticket for an explicit caller retry.

Release refuses Active or nonzero in-flight state. After settlement, it invokes
the host's close callback and removes only that owner's metadata after success.
Close failure/panic retains ownership, namespace/binding reservations and
fencing. Explicit retry is the host's decision and requires a close operation
safe to retry; this API does not automatically retry uncertain external effects.
Business data is never removed by Catalog. No Drop path calls host cleanup or
claims release; an abandoned work handle remains blocked until process recovery.

## Limits that integration must preserve

Catalog owns metadata/admission, not the executing handler, cancellation
implementation, database connection, receipt ledger or recovery policy.
`cancel_requested()` is cooperative intent, never proof that a handler stopped.
`settle_work` is a trusted host acknowledgement gated by successful host
persistence; the type system cannot inspect the callback's fsync or prove that
the host acknowledged truthfully. This is a same-process trusted built-in API,
not a malicious-plugin sandbox or authority grant.

Stop/poll/release are nonblocking Catalog transitions. A drain deadline reports
the still-Draining state to the caller; it does not evict work. Do not wait for a
handler while holding the mutex that its completion needs. Callbacks must be
synchronous and must not reenter the same Catalog/lock. The host is responsible
for its actual final/unknown durability and resource teardown implementation.

Protocol close's existing `{ok:true}` acknowledges fencing/transient ticket
closure; it does not report owner resources Released. Typed owner_state exposes
the distinction. Host adoption is explicit and still requires LeaderB's
integration review against its current store candidate. No new Service/Binder
ABI, grants/default Auto/FullAllow policy or receipt fields were introduced.

## Verification and status

Tests are in `core/tests/owner_lifecycle.rs`; new implementation is the private
`core/src/lifecycle.rs` module with minimal hooks in existing `core/src/lib.rs`.
No schema.rs change was needed. [API.md](API.md) is the integration contract.
[LEDGER.md](LEDGER.md) records RED/GREEN commands and scope decisions; raw logs
remain under evidence. The initial nine tests failed against a compilable
refusing API (snapshot retained), not just missing symbols; cooperative cancel
has a separate behavior RED. Later quota/exact-removal/result/host-marker checks
are supplementary regression coverage and are not mislabelled as feature RED.

PIP-05 and the independent Catalog part of PIP-06 are implemented here. Actual
host handler drain, durable receipt failure, process recovery and Android/device
behavior are not certified by these callbacks/tests. The local filesystem test
uses a disposable host-completion marker and business sentinel, not production
receipts or a real user DB. No user data migration, HTTP/reopen, provider/model
network, I04 action or equivalent ran. I04 DENIED_BEFORE_EXECUTION/BLOCKED and
all dependent merge holds remain unchanged. No main/develop merge or deployment.
