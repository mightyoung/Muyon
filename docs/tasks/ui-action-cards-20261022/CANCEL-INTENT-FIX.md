# Cancellation display correction

Parent independent review identified an Important missed in the initial card review: `cancelRequested=true` can come from the purely local contract `PendingPhase.CANCEL_REQUESTED`. It proves neither remote dispatch nor successful cancellation. The previous unconditional text “取消请求已发出” overstated that evidence.

The model now projects `cancelIntentNotice` as “已记录取消意图；尚未确认取消；取消不代表回滚。” only when the host reports local cancellation intent. ReceiptCard renders that shared projection. When intent is absent the notice is null. Original query/cancel identities, capabilities and terminal status remain host-owned; no real cancellation or service dispatch occurs in this patch.

Two existing Compose behavior cases now assert the accurate notice and absence of the old dispatch claim, for unknown receipts and for a locally recorded cancellation request while the status stays running. These Compose assertions are authored but NOT_RUN due to missing Gradle/Android environment.

## Actual retained evidence

The earlier final 43-assertion and three-mutation outputs were visible in tool results but their original complete local logs were not retained. They are NOT reconstructed or described as recovered. At the parent's explicit request, fresh reruns on the exact previously delivered source HEAD `0519403abdf0f23e9104a022c3c4c8629ef1e1f3` were captured before changing the label/tests:

- [43-assertions-rerun.log](evidence/43-assertions-rerun.log): UTC timestamp, HEAD, exact command, raw stdout/stderr, exit 0, 43 PASS.
- [3-mutations-43-rerun.log](evidence/3-mutations-43-rerun.log): UTC timestamp, HEAD, model/test SHA-256, raw compile/runtime output for all three safety mutants. Each compile exits 0, then runtime exits 1 with `IllegalStateException: Check failed`; 3/3 killed. These intentionally failing mutant runs are expected sensitivity results, not a failing production suite.

The new `src/test/.../ui/cards/run-mutations.py` reproduces those three temporary mutations using KOTLINC; it never edits production files or contacts the host. The runner asserts actual runtime failure rather than treating compilation errors as mutation kills.

For the correction, first extract the existing label into a pure model projection unchanged, then add the new label/null assertions:

- [cancel-intent-RED.log](evidence/cancel-intent-RED.log): actual runtime assertion failure against the extracted old misleading label, exit 1.
- [cancel-intent-GREEN.log](evidence/cancel-intent-GREEN.log): correct label, model SHA-256, strict compiler and runner command, exit 0, 45 assertions PASS (the prior 43 plus two notice checks).
- [cancel-intent-ANDROID-NOT-RUN.log](evidence/cancel-intent-ANDROID-NOT-RUN.log): actual full unit/Android compile/lint attempt, exit 2, missing Gradle. No compilation/render/capture pass is inferred.

The fresh offline logs contain synthetic IDs and assertion traces only. They are now committed at the parent's specific evidence request, superseding this lane's initial choice to keep all execution logs outside the repository. They contain no real business records, credentials or model/search results.

Independent follow-up review and exact outcome are recorded in INDEPENDENT-REVIEW.md. Overall Android/production HOLD remains unchanged. No main/develop edits, real lookup/cancel/retry, deployment, cost or privilege change is part of this correction.
