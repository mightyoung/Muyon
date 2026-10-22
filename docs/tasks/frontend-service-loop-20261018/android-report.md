# Android private supplier chat wiring

Implemented path: existing ChatReadPort -> Application-owned AgentServiceClient -> bounded private IAgentRuntime String methods -> same private :agent AgentRuntimeService -> same retained GeneratedAgentController -> genuinely regenerated UniFFI submitSupplierRead/supplierReadEvents. No second controller, UI store opener, HTTP adapter, authority input or model endpoint was added. The existing summary ABI is unchanged.

The host fixed synthetic schema12 supplier selection is key `11111111-1111-4111-8111-111111111111`, revision `7`. UI input is opaque text bounded to 4096 UTF-8 bytes. This is offline Rust Agent with synthetic business data; no live model API evidence. Production authorization remains fail closed in Rust.

New IPC requests are bounded before generated Binder decode (16KiB full encoded parcel); String replies are bounded by 64KiB UTF-8 semantic JSON and 131200 bytes full encoded UTF-16 Binder parcel. Existing metadata methods retain 4/8KiB bounds and UID checks. JSON envelope, event kinds, payload fields, scalar types, supplier identity, cursor, epoch/run identity and original ToolRegistry receipt shape are validated before display. Completed requires receipt and matching projection. Original receipt identity is retained separately for replay comparison.

Request text, selection, request ID and admitted identity are committed to private SharedPreferences before native submission/accepted presentation. Process restart restores UNKNOWN identity with no answer/projection; reconciliation only polls original request. Disclosure/Binder loss resets the event cursor to zero and clears display values, so lookup can reconstruct the full stream after fresh native disclosure validation. It never re-submits an admitted/unknown request. Cancellation requests old Inquiry control on the same run, marks cancel_requested and looks up settlement. Pending bootstrap performs bounded lease-only observations before the first dispatch; it does not retry native submissions.

Evidence:
- `android-logs/chat-state-green.log`: 11 pure JVM UTF-8/identity/recovery checks PASS.
- `android-logs/recovery-regression-red.log`: reconstructed prior cursor-preserving loss behavior fails recovery assertion; this is a regression reproduction, not evidence of tests preceding initial implementation.
- `android-logs/all-state-green.log`: complete existing stdlib state suite PASS.
- `android-logs/bridge-build.log`: actual Rust bridge plus UniFFI generator build PASS (existing FFI compiler warnings retained).
- `android-logs/binding-generation.log` and `generated-sha256.log`: actual 0.32.2 bindgen run using repository Android config and real Linux .so. Kotlin output was copied from generator; no handcrafted FFI definitions.

Limitations: no Android SDK/device/emulator here, so Android AIDL/Compose compilation, Binder transport, process death and API26 end-to-end instrumentation remain NOT_RUN pending integrated CI. Pure bounds/state tests do not certify the Android JSON decoder or Binder runtime. Native build ID used for generator preparation was B06 `6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa`; final native library must be rebuilt with the integrator's fixed source SHA and matching BuildConfig. No credentials, paid calls or licenses were configured or accepted. I04 remains untouched.

## Fixed-SHA review: pending bootstrap cancellation

Review found that cancelling a submitting chat before its first lease did not remove the deferred submit closure. Added a main-thread PendingChatAction token whose unsent cancellation and dispatch are mutually exclusive. Only a matching original request can revoke it. The client removes the deferred closure, releases the original in-flight slot, and returns definitive local not-sent cancellation. Late bootstrap cannot dispatch that token. Once handed to the RPC lane, cancellation uses native control and waits for settlement; invalid/no ACK is UNKNOWN, never cancel_requested.

Targeted test-first evidence: `pending-cancel-red.log` fails compilation before the token exists; `pending-cancel-green.log` passes seven checks including cancel-before-bootstrap, mismatched request, late dispatch prevention, and dispatch-before-cancel uncertainty. The check is wired into StateChecks; broad suite was deliberately not rerun for this focused fix. Android race instrumentation remains pending integrated CI.

## Fixed-SHA review R4: bounded pending failures

Centralized pending-call failure invalidation and one-shot completion. Busy/rejected handshake, rejected connection application, observe-lane busy/refusal, invisible/stopping connect, visibility rejection/refusal and disconnect complete the original callback with UNKNOWN and preserve request identity. A pending bind/initialization/visibility closure expires after five seconds; its identity-specific timeout cannot cancel a replacement call. Dispatched RPC also resolves presentation to UNKNOWN after five seconds, without retransmitting native work; any later callback is ignored by one-shot completion. Binding an already-pending Android connection is allowed only inside that timeout.

`pending-failure-red.log` records test-first missing fail/completion API failures. `pending-failure-green.log` passes 31 focused checks, covering cancellation/dispatch exclusivity, one-shot failure, six scheduling-failure categories and late callback/dispatch suppression. These are pure state tests, not proof of Android callback ordering; CI instrumentation remains necessary. Broad suite was not rerun for this focused fix.

## Final wire consistency: terminal UNKNOWN disclosure denial

The decoder now uses the tested `finishEnvelope` state helper. A terminal UNKNOWN envelope with zero events is accepted and keeps its native reason (including DISCLOSURE_UNAVAILABLE), clears current answer/projection/receipt, and retains the historical original receipt identity. It remains UNKNOWN, so the existing poll scheduler does not continue and no submit is issued. UNKNOWN with terminal=true and business events is still rejected. `terminal-unknown-red.log`/`terminal-unknown-green.log` record test-first helper failures and 15 focused bounds/recovery/terminal checks PASS; no Android JSON runtime is claimed.
