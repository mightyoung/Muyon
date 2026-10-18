# Scoped final instrumentation correction review

Fixed source `2f8f4da674e871708880dcc792a1c9dafb3a17f3`, exact diff from `44df2265808eee7fba17eb1aae6dc26c3554c3a4`. Only FrontendServiceLoopTest.kt changes. Read-only review; no tests/process actions/HTTP/model operations executed.

**No new blocker or weakening of business/recovery acceptance found.**

The four assertTextContains changes explicitly request substring=true for deliberately partial disclaimer, historical receipt identity and UNKNOWN label text. Exact original receipt identity and invocation_id equality after recovery remain unchanged, as do completed status, exact supplier projection, original receipt owner/binding/identity shape, same-UID distinct Service PID checks, same application child termination, hidden current values after loss, disabled Send and lookup-only recovery.

hideKeyboard uses the actual Activity's InputMethodManager and window token after real Send/Save, then waits for Compose idle. It does not inject execution state, bypass Service work, fabricate results or remove visibility assertions. The Save test still requires empty EditableText, disabled Send and an actually displayed local-only note after scrolling. A device can still fail these assertions if the real behavior is wrong.

This is source approval of the bounded test correction only. Previous immutable73 device evidence establishes the reported happy-path assertions up to its text-selector failure; it does not establish process-death recovery, which was not reached. New exact-source Android build/device/recovery outcome remains pending.
