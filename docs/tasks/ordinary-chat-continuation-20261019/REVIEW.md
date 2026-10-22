# Independent source and execution graph review

Reviewed immutable source: **2fc9ecab381a4106d7680fbb540aeaaa73465193** (parent c1c3ef986efd273225f598e468ce4ed25b427f2a).

Two read-only subagents were used under the user's explicit delegation instruction; LeaderB remained the sole source writer. The first inspected the settled contract and missing coverage and identified that an empty terminal lookup overwrote the original failure reason with envelope `none`. The second independently reviewed the final source and transitive execution graph. Neither modified files or executed tests.

Final reviewer reported no blocking defect:

- The decoder validates request/run/epoch/source before preserving terminal status and reason. Unknown/rejected still lose disclosure.
- Reconciliation publishes a real reconciling state and blocks Send. The original state is captured for decoding; existing ticket/lease/single-completion checks remain.
- The device lookup waits for a new result object with failed status, rather than accepting the unchanged pre-click result. Second success and third exact budget rejection check distinct identities and attempts=2.
- Rust checks exact budget reason, distinct run/task/attempt/admission and frozen current-message payloads; duplicate submit and read-only lookup never exchange again.

Approved graph: standalone Kotlin policy/contract probe; only `cargo test --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test ordinary_chat_controller -- --test-threads=1`; genuine build-only binding reproduction; API26 native ABI producers; `lifecycle_package.py --ordinary-chat`; only OrdinaryChatServiceLoopTest and OrdinaryChatOwnerContractTest instrumentation. No I04/old HTTP/task-state reopen or containing aggregate target is selected.

The isolated lab branch push matches only ordinary-chat-offline. The stacked draft PR targets PR95's lab branch, so develop/main PR gates do not match; the Android Compose PR event's job is skipped by its lab/android-compose-* head guard. Runtime success is established separately by the new run, not by this source review.

## Epoch correction review

During subsequent lifecycle inspection the writer noticed an over-strong test equality between the first historical admitted epoch and the second request after Activity unbind. The reviewer confirmed the miss: Service retirement and a replacement Rust controller generate a new epoch. This was a test assertion defect, not a reason to change product lifecycle behavior.

The independently reviewed correction is **66e4510b56c33ba87649b783903b08cb7538260d**. After recovering the first original request, the test now explicitly refreshes the current Service observation, waits for CONNECTED and a nonempty replacement epoch different from the historical epoch, then requires the second request to use that current epoch. Third failure must retain the second epoch. Agent PID remains the same. Reviewer found no additional blocker; allowed execution graph unchanged. The first CI is retained through its actual terminal; only the corrected SHA can establish final acceptance.

## Submitted-bubble selector review

Both earlier runs reached failure at the device step; their raw job logs returned403 and actual failure points remain unknown. Further source inspection independently established another deterministic selector defect: the Send handler leaves draft text intact, while a global `onNodeWithText(secondPrompt)` searches both ordinary Text and EditableText. The list-scoped scroll does not scope the following global lookup. AndroidX documents this in [its matcher source](https://github.com/androidx/androidx/blob/androidx-main/compose/ui/ui-test/src/commonMain/kotlin/androidx/compose/ui/test/Filters.kt).

Reviewed final correction: **3aaced7281ab7215416841e46edcf8646ad8dfa3**. The assertion now uses unmerged semantics and requires the `service-read-input` ancestor, retaining actual text/display checks while excluding the draft. Independent review confirmed this is the sole code change from66e4510b, does not weaken the assertion and leaves the approved execution graph unchanged. No production, logging or evidence retrieval route was changed. Its changed-source validation is CI39195875864, not a retry of denied evidence. Neither static defect is claimed to be an observed historical CI cause.

## Concentrated complete-test audit

Following the parent's request to converge, a fresh independent read-only reviewer inspected the complete final OrdinaryChatServiceLoopTest and OrdinaryChatOwnerContractTest, plus the Session/ServiceClient/ChatPage/policy/durable-owner/native identity/controller/event recovery chains at **3aaced7281ab7215416841e46edcf8646ad8dfa3**. No source change or additional run was launched during this audit; the already active CI continued without cancellation.

The unified report found no additional statically provable blocker. It checked the historical/current epoch separation, all selectors including retained draft text, two-call total versus per-call reservation and held+consumed SQL, third refusal without an attempt, original-request identity checks before disclosure, captured terminal lookup state/reason, pending-query Send block and new-result completion condition. The direct owner contract's immutable context, payload/capability generation, one-shot exchange and rotation denial match the implementation. Current-message-only wire and latest-request UI limits remain explicit.

Static inspection does not establish real Android scheduling/scrolling/instrumentation success or the causes of the two earlier failures. Only the current CI terminal can settle this source's runtime acceptance. The fresh reviewer did not modify files, execute tests or access any remote log/artifact.

## Final claims review

After CI39195875864 completed, the fresh reviewer read the saved native run/job/step JSON, RESULT.json and HANDOFF.md locally. It confirmed exact source/attempt1/four successful jobs and successful API26 result gate; the script's two-class selector plus required `OK (2 tests)` supports the reported two-test gate. Raw instrumentation and phase TSV remain unavailable and are not presented as read. Product versus test changes, missing continuous context, both earlier failures/unknown causes and the one-shot final own-log403 remain accurately separated. No blocking claim issue was found. Source/workflow diff against the tested SHA is empty. No remote log/artifact read, test execution or file mutation was performed by the reviewer.
