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
