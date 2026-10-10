# LAN upload reliability — bounded investigation

Branch: `task/lan-upload-reliability`; baseline: `b8a9a52308112c9eb2e3a0d2a2f52c87c37b46b9`.

Historical second legal upload HTTP 400 (CI 38016276386) remains unexplained. PR14's diagnostic run did not reproduce it. Do not infer server deadline from client latency, increase 150ms, remove assertions, or label the failure flaky.

Predeclared matrix (each CI run is retained, including failures):

1. Existing 150ms trickle deadline → cleanup → legal upload 200; observe receiver stages and deadline, not client time.
2. Legal complete upload held at a stage until the actual receiver deadline fires; assert 400, no callback/file, counters released, next independent upload 200.
3. Real filesystem rename failure before delivery; assert 400, cleanup, no durable delivered-message record. Keep before-body nonce/message reservation (409 in the same process).
4. Real persistence failure and callback exception; classify stage/error without sensitive values, preserve replay semantics once callback has been attempted.
5. Stop at a pending upload, duplicate requests, idle timeout and absolute timeout; existing trust/replay/restart/security suites and full CI gate.

Diagnostics must be opt-in, in-process, imported from src only, with fixed stages/error categories and numeric cleanup state. Never emit exception text, payload, path, address, IDs, certificate, keys or signature. Timing gates are test capabilities, not network interfaces. No new dependency, workflow, credential or local SDK.

Only fix a reproduced failure. Persisted replay records currently precede file rename; test whether a failed rename wrongly records an undelivered message. Callback failure can have side effects, so never promise automatic safe retry or roll back replay after callback invocation. Crash consistency and async host delivery are outside this narrow patch.

Full CI via existing Actions; raw logs stay in Actions or /tmp, summaries and exact SHAs recorded here. Real Claude narrow review is arranged by the parent before merge. No merge/deploy/main/force push/branch deletion.
