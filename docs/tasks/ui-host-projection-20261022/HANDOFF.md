# Shell handoff

Independent branch `task/ui-host-projection-20261022`, pinned to shell8937b3d6.
Only runtime and Service production files changed. No shell/components/Rust/FFI
or database-write modification. Full behavior/evidence in REPORT.md; non-author
review in REVIEW.md.

Call existing ProductClient.call("chat_snapshot", payload, callback) with original
native request_id, displayed conversation_id, nullable project_id and the integer
scope_generation from the actual chat_scope reply. Runtime derives Binder session
and trusted workspace in Service, validates captured scope before a local original
lookup, and returns an inner read_only snapshot or unavailable. Keep mounted-view
callback scope checks; do not auto-query historical unknown requests.

The detached observation has exact native status and reserved micro-CNY strings/null.
charged_micro_cny means actual settled cost: only native completed plus strict
attempted=true may expose it; other statuses return null even when ledger charged
is "0". Never display an unknown request's ledger default as a free actual cost.
Original
native child conversation is kept separate. binding=null/capabilities=[] and missing
identities/revisions/tasks/sources explicitly unavailable. It cannot be coerced into
CardBinding or an actionable typed card. Do not substitute request_id for intent,
create a revision or revive cancelled/pending execution. Existing confirmation/cost
gates remain required. This slice does not implement trusted core write contracts.

PASS: new runtime offline behavior; existing cards45; contracts20groups; existing
runtime settlement/revocation JVM3tests; independent static+actual offline rerun.
Android command NOT_RUN exit2: Gradle8.13 absent. No SDK retry/bypass; Service build,
lint, instrumentation, device captures and full UI adoption remain open.
Historical2 unknown / ¥0.002620 unchanged. No main/develop edit or automatic merge.

## Continuation endpoints — latest source delivery

Read UI-HOST-PROTOCOL.md (schema1, protocol-first473c13f1) and
UI-HOST-CONTINUATION-REPORT.md for the subsequent implementation commit.
New fixed methods chat_card_candidates and chat_setup_draft; chat_snapshot schema1
is unchanged. Candidates only support explicit original local query, no execute/
cancel binding. Local setup reuses canonical BotSetupDraft, genuine ephemeral local
ID and local CAS, finite local edits/template suggestions/cancel/resume; never backend
save/create/start. Empty skill/material offers explicitly mean metadata unavailable;
no replacement document truth. Shell chooses one draft source of truth and retains
mounted scope guards. Backend identities/CAS/documents and Android acceptance remain
open. Producer endpoint implementation is source-delivered, not shell wiring.

## Persistence continuation — unavailable in product

PERSISTENCE-OWNER-CONTRACT.md and PERSISTENCE-REPORT.md describe the verified gaps
and tested store API. Canonical49ad export/restore dependency is combined; dedicated
HostDraftStore uses its binary archive with stable owner/record envelope and exact
CAS. It is NOT instantiated by production. Runtime now returns
setup_persistent_owner_unavailable for save/restore, with persistent_owner_status
and persistence_status unavailable; saved/can_save remain false. Do not wire a save
button from standalone store tests. Stable owner join, trusted rollback anchor and
unresolved creation/stop guard are still required and cannot be made from session/
generation, checksum, an archive or a fabricated installation/account ID.

## Save-consumer preparation

HostDraftSaveState.kt is backend-independent, executable-tested receipt/export
consumer logic only. SAVE-CONSUMER-REPORT.md gives exact late/unknown/repeat/lease
semantics. No private native wire schema or RPC is guessed; no production save flag
is enabled. The assigned Rust owner supplies fixed SQLite descriptor/save/load/
original-receipt API next, then Runtime/Service adaptation can use this consumer.

## Shared reader next dependency

Read READER-HOST-BRIDGE-REQUEST.md for exact new Kotlin file ownership and proposed
native read-session/list/check/chunk/close contract for the assigned sole FFI owner.
No reader/shell/Rust file was edited or final reader2 combined. First bridge is read
only via controlled typed PFD, not a research cache/JSON URI grant. Annotation save
stays disabled until reader capability gate and original intent/immutable-anchor/
receipt transaction gateway are fixed. Existing annotation revision CAS alone is
insufficient for durable recovery.

## Fixed native consumer checkpoint (supersedes earlier owner-gap description)

NATIVE-CONSUMER-REPORT.md gives implemented Runtime + strict adapter/session API,
exact shell additive schema1 and remaining release blockers. Real local_workspace
BusinessStore+live project ownership is sufficient for this new editing-only domain;
no account ID, cloud secret or root-rollback protection is required or invented.
Native baseline7ca2 has fixed-source3160208247c5257b6382106d69f2028f5ad8ccab;
parent actual Rust verification is pending. Service verified=false remains, and its
four typed methods explicitly unavailable until real generated bindings are composed.
NATIVE-SERVICE-ADAPTER.patch is an unapplied, reviewable exact callsite proposal,
not an enabled function or a substitute for actual native/Android acceptance.

Strict original receipt consumer is wired into Runtime when a verified private port
is supplied, JVM-tested with synthetic native schema/transactions only. Unknown
keeps exact original and returns no editor fields after dispatch/query failures;
read/edit revalidate current native project/registry or exact original lookup.
Cold-process original attempt pointer still needs durable same-store coordination;
never infer original from latest, auto-replay, or announce original recovery complete.
No create/run/lifecycle ledger for execution was added; historical unknowns untouched.

READER-FFI-MINIMAL-SCHEMA.md is the exact five-method minimal read-only request to
sole FFI owner, based on actual canonical DocumentRef/operation/StoreEvidence byte
flow. Reader host/PFD implementation remains pending released native and reader2
read-only gate; annotation immutable-anchor/original-intent transaction remains a
separate core task. No UI shell/reader ownership was crossed.

Latest parent evidence dc7f1c0c5331c5ecb53e4dfa33c0c0cb3d6b7bfa was fetched/read:
provider316+sole export combo f0ef760ba7253f38be8e26989ca99b82a76acf8b actually passed
provider19/19, core202, scoped fmt0. NULL Rust blocker is now closed. Only real FFI/
generated bindings/cold-process original binding/Android gates above remain; do not
keep labeling the fixed NULL issue pending or infer UI acceptance from Rust PASS.

## Actual Service bridge continuation — latest

SERVICE-BINDING-REPORT.md supersedes older missing-FFI/unapplied-callsite text.
B's exact generated commit8255 is inherited unchanged; current bytes equal B88e810.
Service now actually calls all four generated methods. Provider verified source+
sole export is inherited via merge748daf9b; no direct Rust owner edit. Upstream
Bworkspace405/FFI14 is supporting evidence, not a fresh run of this feature branch.
Current consumer actual JVM runner and non-author review PASS; Android still NOT_RUN.
verified=false now only preserves cold-process original-attempt/Android gates, not
old closed NULL/cache/API gaps. Exact durable pending-journal request is in the report
for sole Rust owner; it must supply real outstanding original pointer, never latest.

## Cold original preparation consumer — latest

COLD-PREPARATION-CONSUMER.md supersedes earlier missing cold-pointer consumer work.
Fixed098 five-method schema is implemented in Host session/codec and synthetic
Runtime tests: await exact prepare before save; resolve AND read pointer discovery;
only explicit query_original_save may fence; definite not_committed allows a NEW
explicit save; no replay; cold numeric0/0 never acknowledges a new reducer; restore
is separate and refuses a new read-discovered pointer. Terminal state and full
original binding stay monotonic. Independent actual runners/repros passed, review
findings repaired; raw intermediate failures retained. Service fifth method still
explicit unavailable pending B actual fifth generated binding; exact prepared patch
is NATIVE-PREPARE-SERVICE.patch, no missing method referenced. verified=false.
Parent upstream Rust26/core209/probes3 and purefmt111e pass are recorded accurately;
new five-method FFI/Android acceptance is not inferred from previous four-method pass.
