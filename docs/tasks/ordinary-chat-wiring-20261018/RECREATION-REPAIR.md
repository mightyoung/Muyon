# Activity recreation acceptance repair

Base: **0345822d919411b17f5c082c362e03da66d55290**. Authorized scope: diagnose
CI39183528428's own failure, make the smallest justified repair, independently
review it, execute targeted socket-free checks, then one new API26 acceptance.
All historical log/artifact denials and I04/HOLD/model/credential/fee restrictions
remain unchanged. CI39144821029's unavailable cause is not inferred from new runs.

## Root cause

New CI39183528428 actually ran both tests. The Compose test failed at line 56's
second Send enabled assertion after Activity recreation. Its instrumentation
output records the button as Disabled; first-send/receipt and recreated identity
assertions precede the failure. This is the retained red integration regression,
not a reason to remove the Send assertion or wait for it to turn green.

The lifecycle/source chain establishes the missing test step:

- `MainActivity.onStop` publishes last-Activity invisibility.
- `AgentServiceClient.sendVisibility(false)` synchronously calls
  `AgentChatReadSession.transportLost`, then releases the old lease and later
  publishes the completed stop/unbind state.
- `ChatReadConversation.disclosureLost` sets `unknown`, hides answer/receipt,
  resets cursor, and retains request/run/admitted epoch/receipt identity.
- `frontendCanSend` intentionally denies unknown even with nonblank text;
  `frontendNeedsReconcile` presents the existing query action.
- The old test recreated Activity but never queried the original request before
  expecting another Send. Android idle does not restore business disclosure.

The existing Service slice contract at
`docs/design/android-agent-service-20261015/ANDROID-AGENT-SERVICE-SLICE.md:72`
explicitly applies last-lease stop during configuration recreation and requires
reconciliation before another submit. New visibility does not undo cancellation
or automatically resume. Rust event lookup verifies the new current lease, then
looks up the original request and returns its original admitted epoch; no static
requirement incorrectly equates that original epoch with the new current epoch.
The repair therefore corrects the test's missing explicit interaction; production
state recovery, Service lifecycle and sending policy are not weakened or changed.

## Minimal correction and verification

The same Compose test now asserts unknown, disabled Send, hidden disclosure and
stable identity with attempts=1. It waits for the existing final stop/unbind
publication (transport alone becomes UNBOUND before asynchronous stop completes),
clicks the existing `reconcile-service-read` button once, and waits for verified
completed disclosure. It checks the same request/run/original admitted epoch,
receipt identity, answer and attempts=1, then retains the original second Send
enabled/click, failed status and one-attempt quota assertions.

The bounded wait observes a specific lifecycle completion signal; it never waits
for Send to become enabled, adds no sleep/retry, and does not directly call the
Service/reconciliation API. No replacement demo entry or new product hook exists.

The standalone `OrdinaryChatRecreationPolicyProbe.kt` imports only the actual
ChatReadContract and FrontendChatPolicy. It verifies hidden unknown disclosure,
stable identities and refusal to submit nonblank text before a verified terminal
view. It deliberately supplies a completed view to test policy only; it is not
Binder/recovery runtime evidence. Only these three files were compiled to a new
temporary jar and executed. Kotlin 2.2.20 tool archive was downloaded separately
and verified against the repository's pinned SHA256
`81f0264c9073b5cbbdb3ff8418cf2c5dac076879fc156fa1a6462f5a5acc4420`;
compilation and the probe itself perform no network access. Evidence is in
`evidence/recreation/policy-{compile,run}.log`. No aggregate suite was executed.

Exact targeted command (paths rooted at this checkout):

```sh
/tmp/ordinary-chat-kotlin-tool/kotlinc/bin/kotlinc \
  experiments/redesign/android-compose-lab/state/src/main/kotlin/com/mightyoung/muyon/androidlab/ChatReadContract.kt \
  experiments/redesign/android-compose-lab/state/src/main/kotlin/com/mightyoung/muyon/androidlab/FrontendChatPolicy.kt \
  experiments/redesign/android-rust-bridge-lab/checks/OrdinaryChatRecreationPolicyProbe.kt \
  -jvm-target 17 -include-runtime -d /tmp/ordinary-chat-recreation-check/policy.jar
java -jar /tmp/ordinary-chat-recreation-check/policy.jar
```

Targeted result: PASS. Actual Android query/rebind, disclosure restoration and
second-send quota validation require the single new CI's own terminal evidence.
