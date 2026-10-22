# Scoped API26 instrumentation selector review

Reviewed fixed `73a582d3c948d70450a45da4205435a715eeb6b4`, supplied `fa176→73a582d3` diff only. Read-only; no tests or production-code re-review performed.

**No weakening of the real acceptance gate found.**

- Sent prompt assertion now requires exact prompt text inside the tagged submitted-message subtree. This excludes the still-populated editor while still requiring the actual rendered submitted prompt.
- Local Save assertion now directly checks the draft node EditableText equals an empty AnnotatedString. This checks editable state rather than mixing placeholder Text semantics into the match. Disabled Send and rendered local-only note assertions remain.
- Completed status, exact synthetic supplier projection, ORIGINAL ToolRegistry receipt identity/binding/invocation shape, distinct same-UID Service process, Service kill, UNKNOWN/current-value hiding, lookup-only recovery and unchanged receipt identity/invocation assertions are unmodified.
- logcat clear/dump are bounded auxiliary observations whose failures are explicitly recorded as UNAVAILABLE. Instrumentation invocation, exact two-test success check, failure/crash rejection and process evidence command remain mandatory; auxiliary log availability is not substituted for successful instrumentation.

These changes correct selector ambiguity and optional log collection without replacing the actual UI/Binder/native/recovery exercise. Actual exact-SHA CI39106124839/API26 outcome remains pending and is not certified by this source review.
