# Manual verification hold continuity

Task branch: `task/harness-manual-hold-identity`; draft PR #20. Baseline:
`38f2040bbdb7b7d0f766891c94c3440d208a7f6c` (PR16 merge). Parent alone integrates;
this task does not merge, deploy, force-push, delete branches or alter credentials.

## Problem and short plan

[PR16 postmerge Codex review](https://github.com/mightyoung/Muyon/pull/16#pullrequestreview-5477387202)
identified P1: `_manual` saved a verification task without its historical
invocation ID or digest. Pausing that card overwrites stage; resuming sees no
receipt and falls back to a fresh executable card before verification.

1. Demonstrate the duplicate effect with a real local handler/receipt and a
   persisted interrupted checkpoint; exercise repeated pause/resume with actual
   database close/reopen, damaged/missing/mismatched digest and unknown receipts.
2. Preserve historical identity and budget, and treat persisted `preview.resume`
   as an unacknowledged stop independently of stage or later receipt changes.
   Carry already-broken old holds conservatively; never invent a digest.
3. Keep acknowledgement distinct from normal subsequent tool authorization.
   No-grant tests require the fresh tool confirmation and one-time approval;
   existing valid grant policies remain unchanged. This patch does not claim
   that every authorized configuration requires two manual clicks.

## Validation and review evidence

- Tests-only candidates with incorrect descriptor construction / terminal-state
  fixture updates were corrected before accepting RED. Pending or cancelled
  earlier runs are not evidence of the P1.
- Valid RED: `80aae66cd67472e6fc8f46412f1a76085fdbb2af`,
  [PR CI38022126443](https://github.com/mightyoung/Muyon/actions/runs/38022126443)
  completed failure: analyze8/8 passed; host `+1459 ~3 -23`; exactly the 23
  new cases failed. Actual effect counter expected1/actual2; other 22 cases
  expected `resume`/actual `tool`. Other package suites passed. The PR checkout
  merged this tests-only head into develop8debfd2172b9fc3a9d2cca53fc4d92abe913cd4d.
  No compilation or precondition failures were accepted as risk evidence.
- [Exact-head push CI38022123815](https://github.com/mightyoung/Muyon/actions/runs/38022123815)
  also completed failure with the same analyze8/8, host `+1459 ~3 -23`,
  duplicate counter1/2 and 22 resume/tool assertion failures. Other suites passed.
- Standalone fixture has no network/model: real FoundationRepository,
  ToolRegistry and SQLite storage; handler counter persists across DB reopening.
  Tool time uses a deterministic host clock, not sleeps.
- Existing Linux Actions run all eight analyze/test packages and Laya scripts;
  no Mac build, device test, real model or external attack path is claimed.
- Independent session inspected the implementation/test diff and found no
  blocking static issue: marker checked before receipt/adoption/fresh, historical
  evidence/usage retained, legacy holds kept, authorization policy untouched.
  This is static Codex review, not dynamic validation or Claude review.
  Real Claude narrow review
  remains a parent-session gate; no callable Claude entry is available here.
- Raw logs stay outside the repository. Final fixed SHA, CI terminal results and
  complete narrow review package are recorded in draft PR20.

## Review scope

Baseline-to-final diff, `agent_resume.dart`, `manual_resume_hold_test.dart` and
this evidence; read-only context: PersonalAgent pause/resume/confirm,
AgentDispatch dispatch/_stage/_openCard and ADR0005 recovery/authorization.
No message model, permission, schema, Dream/foundation or grant-policy rewrite.
