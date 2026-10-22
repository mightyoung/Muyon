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

The detached observation has exact native status and micro-CNY strings/null; original
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
