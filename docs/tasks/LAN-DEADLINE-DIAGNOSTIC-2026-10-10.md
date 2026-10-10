# LAN deadline diagnostic — bounded execution plan

Base/source: 2cb616c429a5e27cf3b43e7af93f7eb5d9efca93.
Original failure: Actions run 38016276386/job 114107129202, legal second
upload returned 400 rather than 200 after the trickling request was closed
and inbox cleanup passed. The historical server exception was not recorded.

Run budget fixed before push: one push-triggered existing ci workflow run,
one unchanged full-suite invocation; no retry to select a passing result.
Purpose: capture response status/body size, client phase elapsed times and
observed cleanup ordering. A pass means not reproduced, not a root-cause
diagnosis; a repeated 400 with empty body still requires server-side evidence.
Infrastructure failure is reported as such, not silently retried.

Keep transferTimeout=150ms, uploadIdle=300ms, all cleanup checks and expected
HTTP 200. Diagnostic helper affects only this test; response content, secrets,
payloads and filesystem paths are never logged. ci.sh emits only the bounded
LAN_DIAGNOSTIC labels even when the suite passes, preserving every suite and
exit-status gate. No workflow, production code or PR14 source branch change.

Server internal phases are not visible through the current API. If needed,
minimal proposed instrumentation is an isolated diagnostic observer reporting
request ordinal, monotonic elapsed time, deadline/stopped flags, fixed stage
and fixed exception classification at _acceptPush/_serve, without changing
control flow, timers, responses or cleanup. That production entry is not
implemented in this commit; no general observability redesign is proposed.

Local validation: git diff --check, bash -n scripts/ci.sh and the nine existing
test_verification_gates.py regressions pass. No local Flutter/Dart SDK;
analyze/test validation is delegated to the existing Actions runner.
