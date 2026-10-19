# Activity recreation — verified bounded outcome

Tested source: **f86804cce3f54888ef0cc42b0540d12fb82e42c7**.
The sole new authorized [CI39184565190](https://github.com/mightyoung/Muyon/actions/runs/39184565190),
attempt 1, reached terminal **completed / success**. No rerun or cancellation.
All four jobs succeeded: scoped Rust/binding, native arm64-v8a, native x86_64 and
package-device. APK/test APK/lint/package inspection and all six device phases
succeeded. New job **117844503603**'s own log was read successfully once and its
device output is archived in `evidence/recreation/`, together with full terminal
metadata, derived SHA-bound phase TSV and RESULT.json. No artifact was downloaded.

## Root cause and actual fix

This was a test interaction error, not evidence requiring weaker product recovery
or a longer arbitrary synchronization delay. Activity recreation stops the last
visible lease; `transportLost` intentionally hides business disclosure and changes
completed to unknown. `frontendCanSend` forbids unknown until explicit original
request lookup. The previous test omitted that lookup and failed at its second
Send enabled assertion (CI39183528428, line 56, retained with Disabled semantics).

Only the test was repaired: assert unknown/nonblank disabled Send, wait for the
existing old-stop/unbind completion signal, click the real query button once,
verify recovered original answer/request/run/admitted epoch/receipt identity and
one durable attempt, then perform the unweakened second Send, failed-status and
attempt-count assertions. No production logic, fallback path, automatic resend, test hook or
arbitrary sleep was added. See RECREATION-REPAIR.md and RECREATION-REVIEW.md.

## Evidence sets and limits

PASS:

- Local standalone pure Kotlin disclosure/identity/send-policy probe. Only two
  production policy files and its standalone probe compiled/executed; no suite.
- CI scoped ordinary_chat_controller: six Rust controller regressions and actual
  UniFFI build/generation/byte comparison, as selected by the exact workflow.
- Both exact-source API26 native ABI producers; APK/test APK/lint and packaging.
- SDK, AVD, boot, install, instrumentation and result checks: all exit 0.
- AndroidJUnitRunner `OK (2 tests)`, both class completion status codes 0.
  `OrdinaryChatServiceLoopTest` now completes ordinary Send -> private Service ->
  same Rust Agent -> synthetic provider -> same conversation response, separate
  Service PID/UID checks, Activity recreation, explicit read-only reconciliation,
  original identity restoration, second explicit send failure and attempts=1.
  The test does not separately assert a specific budget failure code, so that
  reason is not independently established by this result.
  `OrdinaryChatOwnerContractTest` also passes its context/generation/one-shot checks.

FAIL, retained:

- CI39183528428 at d9892a75775e507d585f3ddaa712305be30dcfac: owner test PASS;
  Compose test FAIL at second Send Disabled after missing reconciliation.
- CI39144821029: overall FAILURE; historical device cause and individual outcomes
  remain unknown. No access to its denied logs/artifacts. Earlier compile/native
  failures and observation-probe red evidence remain unchanged.

NOT_RUN / still blocked:

- Prohibited I04 old task.db -> HTTP -> reopen and every containing aggregate
  suite; PR86 and dependency-combination HOLD remain in place. No combination
  merge/release evidence is supplied by this isolated PR95 result.
- Seven physical-device items, real foreign constructor/destructor/SQLite.close
  exceptions, real provider/production transport acceptance and previously
  deferred migration/retention cases are not established by this emulator run.
- Production remains unconfigured/default-deny. Real model ID, currency/spend
  ceiling, total token/price proof, installed authorization/profile/provenance/
  credential identity-generation-revocation owner with retention, and reviewed
  authorized HTTPS adapter/real acceptance still need their own authorized slice.
  Settled mode/FullAllow choices are not reopened.

No .env/key reads, credential setup, real/paid model call, merge into develop/main,
HOLD removal, deployment, force push or branch deletion. Source writer stopped
after f86804cc; later updates are documentation/evidence only.
