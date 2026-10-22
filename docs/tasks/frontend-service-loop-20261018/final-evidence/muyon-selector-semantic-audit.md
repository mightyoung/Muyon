# Final instrumentation selector semantic audit

Immutable source: `2f8f4da674e871708880dcc792a1c9dafb3a17f3`. Reviewed the full FrontendServiceLoopTest.kt, including the accumulated989/fa/73/2f selector changes. Read-only source audit: no tests, process actions, HTTP or model operations executed.

| Old failure / ambiguity | Final assertion and reason |
| --- | --- |
| Prompt appears both in still-populated draft and submitted message | Line51 requires exact hasText(prompt) AND the service-read-input tag or its descendant. Draft text or unrelated controls cannot satisfy this subtree requirement. |
| Empty editor placeholder is included in assertTextEquals | Line119 checks the tagged assistant-draft EditableText property equals empty AnnotatedString. It directly checks editable content; placeholder Text is irrelevant. Disabled Send is still separately mandatory. |
| Disclaimer node contains a full sentence, while intended checks specify only partial phrases | Lines67-68 use substring=true only on the exact port-disconnected node. Both synthetic schema12 and no-real-model phrases remain required. Matching a phrase elsewhere cannot pass. |
| Historical receipt node contains explanation around the original identity | Line84 uses substring=true only on service-read-historical-receipt and requires the captured original identity. Recovery then compares decoded receipt identity and invocation_id by exact equality at100-101, so the historical substring match does not replace identity continuity. |
| UNKNOWN label is longer than 状态未知 | Line85 uses substring=true only on service-read-status. It remains paired with absent current receipt/projection and disabled Send. A matching unrelated text/control cannot pass. |
| Keyboard obstructs scrolled local note | Actual InputMethodManager hide + Compose idle occurs after Send/Save. Lines121-122 still scroll to the exact local-only note label and require assertIsDisplayed; this is not reduced to existence. |

## Mandatory acceptance invariants retained

- Real Activity/MainActivity entry point; no mock port, fake Service response, test success state injection or receipt fixture is installed.
- Exactly one Send click exists in the happy-path test (line46). After process termination there is no text replacement, second Send, retry helper or direct native invocation: only the tagged reconcile-service-read control is clicked at91.
- Exact completed status and exact 合成供应商甲 projection are mandatory before loss (54/57-58) and after lookup (94/96).
- Original rendered receipt must parse as JSON and satisfy exact ToolRegistry owner, host-supplier-name-read binding, nonempty invocation and a full32-lowercase-hex identity. Recovery requires exact equality of original identity and invocation_id. Neither disclaimer/history substring selector substitutes for these checks.
- Original process lookup uses exact application package :agent name, requires same UID and PID distinct from UI, repeats checks before targeted Process.killProcess, and requires a same-UID restarted :agent with PID distinct from both old Service and UI.
- After kill, test must observe tagged historical identity and UNKNOWN status, absence of current receipt/projection, disabled Send, then perform original-request reconciliation and receive completed projection/unchanged receipt. Thus killing a wrong control/process or merely leaving a happy-path result on screen cannot satisfy the full sequence.
- Input validation still checks blank, whitespace and oversized UTF-8 cases through disabled Send; Save still requires the empty editor, disabled Send and visible local-only note. These assert UI behavior; they do not alone prove backend non-dispatch for invalid input.

**Conclusion: no selector-induced weakening or wrong-control green path found in this final test source.** Partial text matches are all tied to their intended exact tags; the submitted prompt uses an exact text-plus-subtree constraint. Business identity, completion, process boundary and recovery checks remain mandatory.

Evidence boundary: the configured acceptance platform is a CI Android API26 x86_64 emulator, not a physical Android device. Physical-device execution is NOT_RUN. Previous immutable73 emulator output reached happy-path receipt/projection checks but failed a disclaimer selector before process-recovery execution; recovery was NOT_RUN in that run. This source audit does not establish a new emulator PASS or any physical-device success. The new exact-SHA emulator execution must supply that result.
