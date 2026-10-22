# Host shell independent review

Reviewed by `/root/review_shell`, 2026-10-22 UTC. Base HEAD `097b86d7e2bdaadf01736289cd54380ea82b9b27` plus uncommitted feature source. Exact SHA256 identities, direct captured runner output and exit code are in [host-shell-independent.log](evidence/host-shell-independent.log). Source hashes were equal before and after execution. Base HEAD alone is not claimed as the tested feature artifact.

## Independent result

`run-host-shell-checks.sh` independently compiled actual ProductChatRuntime, ProductSendGate, ProductHttpsTransport, BotSetupDraft and shell consumers using Kotlin2.2.20, `-Werror`, JVM17 and actual org.json. Both controller/candidate mains passed, exit0; `git diff --check` passed. The controller fixture forbids native-port and transport calls. Candidate fixtures use a bounded fake port and forbid transport. No real ProductService/model/search/paid request was invoked.

Covered: sole host reducer, exact CAS, stale and busy duplicate rejection, suggestion token/manual buffer protection, lost outcome original-ID read without edit replay, cancel/resume, same-CAS immutable snapshot, close callback isolation, re-entry original-ID read and expired-session retention. Candidate tests cover original request/config identity, exact scope, finite read-only kind, binding/action absence, unknown charge suppression and inconsistent duplicated observation rejection.

## Review findings closed

- Same local CAS revision with changed content is rejected.
- ViewModel retains passive original scope/draft identity, while mounted live controllers close. Re-entry reads the original ID; expired scope cannot auto-open replacement identity.
- Late snapshots/templates do not overwrite unsent manual buffers.
- Reopening says “放弃本页恢复绑定，重新打开宿主草稿（保留文本）”; it does not promise a new ID because Runtime open can reuse the scope-owned draft.
- Candidate clicks capture the displayed original request, compare it with the mounted request and perform scoped local reads. No CardBinding, execution/cancellation authority or business intent is fabricated.
- A subsequent actual runner failure exposed completion publication ordering: polling could observe busy=false before final snapshot/needsRead. The reviewed fix sets snapshot/recovery fields first, then publishes volatile busy=false, then notifies. This report uses a fresh independent post-fix run. The parent retains [the original failure](evidence/host-shell-completion-publication-red.log).

No outstanding Important finding was identified in this bounded source review. This is not whole-app/all-UI acceptance.

## Retained limitations

The parent actually ran Android Gradle; [host-shell-android-build.log](evidence/host-shell-android-build.log) fails before compilation at AGP8.11.1 resolution. The reviewer inspected that failure, but did not independently rerun Gradle. Compose signatures/layout, actual Activity/client/IME/Back/rotation/TalkBack and instrumentation remain unverified on Android. Pure controller tests do not establish those results.

Drafts remain host-session memory only. Durable save, formal Bot creation/start, production typed-card gateway and Office reader/editor are not delivered here. Deferred local-file storage probes are not production persistence evidence. Existing unknown operations/held fees remain untouched; no automatic historical query, resend, refund, merge or deployment occurred.
