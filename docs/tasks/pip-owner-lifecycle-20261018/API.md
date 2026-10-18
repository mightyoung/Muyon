# Minimal trusted Rust integration seam

Import `Catalog`, `OwnerLease`, `WorkLease`, `DrainState` from the existing
`muyon_plugin_contract_lab` crate. No new JSON lifecycle endpoint exists.

| Method | Meaning |
|---|---|
| `register_owned(bundle: Json, host_bindings: Vec<String>, host_data_admissions: Vec<String>) -> Result<OwnerLease>` | Existing closed atomic registration plus opaque host lease. Module names remain bundle metadata; lease identity/epoch are not plugin input |
| `OwnerLease::epoch() / generation() -> u64` | Owner epoch and registration publication generation; owner lease remains valid across unrelated generation changes |
| `dispatch_owned(&OwnerLease, ticket: &str, authority: Json) -> Result<(Json, WorkLease)>` | Existing invoke success reply and retained host work. `ticket` is from existing prepare. Actual authority checks remain mandatory |
| `WorkLease::ticket() -> &str` | Original transient ticket for optional accept_result/cancel |
| `WorkLease::cancel_requested() -> bool` | Thread-safe cooperative request set by stop, cancel or close; not a terminal outcome |
| `stop_owner(&OwnerLease) -> Result<DrainState>` | Fence new admission; reject dependencies still registered; request cooperative cancellation; never wait |
| `owner_state(&OwnerLease) -> Result<DrainState>` | Active, Draining{in_flight}, or Released. Stale same-Catalog epochs return Released; foreign leases error |
| `settle_work(&WorkLease, persist: impl FnOnce() -> Result<()>) -> Result<()>` | Host-only acknowledgement AFTER actual quiescence, with successful original final/unknown persistence callback. Success consumes remaining transient ticket; repeated success skips callback |
| `release_owner(&OwnerLease, close: impl FnOnce() -> Result<()>) -> Result<DrainState>` | After stop and zero work, synchronous host resource close followed by exact removal. Failure retains fencing; stale disposer no-op |

All Result errors are existing crate `Result<T> = Result<T,String>`. New explicit
errors include foreign_owner/foreign_work, owner_stopping, owner_active,
owner_draining, owner_has_dependents, work_owner, owner_work_limit,
owned_dispatch_required and checked counter exhaustion. Host callback errors
propagate without converting unknown to success. No receipt is manufactured.

## Execution order for LeaderB's future adapter

1. Trusted setup retains the OwnerLease returned by register_owned. Keep legacy
   enrollment if the adapter has not adopted this contract; no implicit opt-in.
2. Use existing prepare with the original invocation/receipt identity and current
   authority. Pass its ticket and re-sampled authority into dispatch_owned.
3. Retain WorkLease before entering the existing host durable-begin/authority/
   handler path. Observe cooperative cancellation through the host's existing
   control mechanism. The returned JSON is dispatch metadata, not handler output.
4. Once handler stops, follow existing host receipt/outcome rules. A successful
   result may use existing accept_result while owner remains Active and all
   original authority/receipt/schema checks pass; acceptance alone does not settle
   tracked work. If stop wins, do not publish a result or auto-replay the request.
5. Call settle_work after optional accept_result, with a callback that persists
   the original host final/unknown evidence. On failure retain the lease and
   fencing and follow existing recovery policy. The callback must be safe for an
   explicit retry; Catalog never schedules one. Do not acknowledge before actual
   handler quiescence or substitute an empty callback in production.
6. For unload, release dependent consumers first, call stop_owner, request/wait
   for actual host cancellation outside the Catalog lock, and observe Draining.
   A deadline leaves Draining visible. Settle remaining work as above; call
   release_owner with actual resource close only at zero in-flight.

Catalog accepts `&mut self` transitions, so its caller serializes them. WorkLease
clones may be held by a worker and polled across threads, but Catalog does not
execute that worker. Never hold its lock across await/join or reenter it from a
callback. Dropping a handle performs no implicit success or cleanup. Unload never
deletes business records or rolls back committed external effects.

The local tests exercise real Catalog admission and the lease transitions with
controlled host callbacks. They do not replace the needed host wiring tests and
actual Android acceptance. LeaderB owns all rust-agent-host-lab changes.
