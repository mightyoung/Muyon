# Independent non-author review

Reviewer: delegated `host_projection_review`, read-only, no code/commit/push.
Base reviewed: 8937b3d62943351f918b4ae980f987e804427911.

Initial review found two changes to fix:

1. Display cache capacity had accidentally become a new business prepare gate.
   Reviewer reproduced successful prepare256 / unavailable prepare257 using actual
   runtime with a local fake port. Fixed by pure-display FIFO eviction, removing
   all added business admission limits and clearing invalidated session origins.
   New257-prepare regression verifies both continued prepare and safe old-display
   unavailability.
2. Native tool_consumed status was omitted. Fixed by preserving the raw fact while
   keeping execution_status unavailable. Regression added.

Final independent rerun of actual runtime Kotlin JVM projection tests: exit0,
output retained in evidence/independent.log. Static Service boundary and complete
runtime diff reviewed; source diff check passed. Whole final staged archive has
a raw JUnit trailing-blank-line whitespace warning, retained unchanged as documented
in REPORT.md; this is not a source/test failure. No unresolved new blocking issue
found within this request-read slice. Missing provenance safely returns unavailable
rather than altering successful business preparation.

Reviewer confirmed pre-lookup scope rejection, exact original request query,
no answer/command exposure, unknown/null cost preservation, no invented identity/
revision/digest/authority, no new write/dispatch/refund, and current_business_state
null for historical observations.

This is not approval of integrated Android behavior or full typed-card adoption.
Android build/device tests are unexecuted because existing Gradle is absent; SDK
installation remains stopped after earlier denial. Full ComponentSnapshot/CardBinding,
intent/CAS/task/source producers and actual shell adoption remain open. Leader B
retains integration authority; this branch does not merge into develop.

## Parent actual-charge Important — fixed and independently reverified

Delta from ac55ef65a65baf9499fe2e4b3a63a0baaf827887 independently reviewed by
host_projection_review. Confirmed native requests.charged DEFAULT0, dispatch claim
attempted=1, and validated settle_response transition to completed/charged. New
public actual charge gate requires completed and strict Boolean attempted=true.
Unknown raw0/positive, other statuses, and missing/false/string attempted keep actual
cost null. Reservation remains its original field; no ledger operation changed.

Test-first actual-native-shape RED retained. Non-author actual current runner rerun
exit0; output evidence/charge-proof-independent.log. Full new fee-proof behavior,
identity/scope/unknown/capacity regressions pass. No new blocker found in this pure
projection delta. Reviewer suggested clearer wording about conservative handling
of other statuses; source comment corrected without changing behavior.

Only projection, corresponding tests and documentation/evidence change. No old
unknown query/retry, billing state change, Service authority change, or live request.
Android/toolchain and full-card limitations from initial review still apply.

## UI host continuation independent review

Reviewed delta from98e5b652 by the non-author host_projection_review agent. Final
actual new runner rerun exit0, two PASS lines in continuation-independent.log;
authored source diff check passed. Reviewer confirmed original-request/configuration
separation, unknown cost proof retention, null binding/disabled execute/cancel,
strict local CAS/id/scope/token/repeat handling, cancelled-draft isolation and
capacity32 with no business request gate. Setup tests report zero private-port calls.

Initial state-independent next/back/suggest enablement was flagged and fixed:
localSetupActions is shared by output and operation handler, with step/required-field
regressions. Strict edit value String validation avoids generic failure/port path;
numeric/null tests confirm no overwrite. Final metadata unavailable flags and
no alternative Rust documents source were verified. No new blocker identified in
this host-only API slice. Actual Android Service/build/device, full card binding,
backend persistence/create and shell adoption remain open. No review merges or
changes were made by the reviewer.

## Persistent storage frame final independent review

Non-author host_projection_review reviewed actual canonical-codec store and ran its
synthetic tests, final nullable-floor version exit0. Original output in
persistence-independent.log. No production store caller or owner bypass found;
runtime save/restore remains unavailable. Strict trailing JSON/raw NUL rejection,
existing durable root precondition, real cross-process CAS, atomic replace/sync,
Unknown exact receipt recovery, archive size, valid older frame/floor, anchored0 and
MAX cases verified. Earlier parse/root/floor problems were corrected before this
checkpoint. Fixed49ad codec is reused; no host replica of editing serialization.

Store alone is not an authorized owner resolver or rollback-resistant account
ledger. Production persistence remains blocked by missing verified owner, trusted
anchor and unresolved creation/stop guard. Actual Android and power-loss tests not
performed. Reviewer did not modify, submit, push or touch real app data.
