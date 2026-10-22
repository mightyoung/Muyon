# Private Linux offline native read host

This experiment composes the existing Agent drive with a real contract child.
Host-installed Rust handlers read synthetic files; the child validates metadata,
tickets and projections. No arbitrary plugin business code, real model, secret,
product database, writable operation or durable live-session resume is provided.

`Enrollment.scope_refs` is mandatory trusted host installation data. It identifies
all selected physical records the installed handler may read, with exact module,
DATA type, key, schema version and object revision. It is not inferred from plugin
labels, candidate output, or a broad scope string. The host installer must bind it
to the same physical handler's key/type predicates. `PhysicalReadHandler.bind_record`
binds an exact reference to its key and optional native type argument; its pure
admission hook rejects other allowed refs before the handler counter or file read. Targets must belong to that
operation's declared DATA. Missing current refs deny before a receipt is begun.
After contract-child invocation and durable running receipt creation, a final live
authority/ref/control check immediately precedes handler entry. Cancellation after
the raw read retains the original receipt and prevents projection admission.

The entire `native.db` snapshot is limited to **65,536 UTF-8 JSON bytes**, matching
its restore parser. The store is deliberately small, not a general business DB.
All writes use validated transaction candidates. The complete encoded snapshot
must pass the same restore parser, including its depth/node limits, before any
atomic write; validating an isolated raw value is insufficient. If a raw handler outcome would
exceed this total budget, the old physical and in-memory running receipt remains;
its outcome is unknown, never promoted to success, exported, or automatically
retried. Any uncertain write poisons further execution/export through that store.
Conservative source facts remain. Reopening validates the complete closed store,
receipt identities, bindings, source facts and status/raw consistency, and exposes
historical evidence only; it cannot restore grants, child tickets or projections.
