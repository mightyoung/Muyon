# Android Service/UI and development model wiring

Prerequisite satisfied for PR119 source b899a326: hosted product CI39954301010 and generic CI39954301004 both completed successfully, with no failed run and no rerun. This evidence covers that source only. The subsequent local Android/FFI/UI changes still require final combined verification and hosted CI on the final candidate; neither earlier run proves the later changes.

Current implementation and verification evidence is tracked in [ANDROID-REPORT.md](ANDROID-REPORT.md). The order below remains the dependency order and acceptance contract; an implemented step is not automatically a completed acceptance gate.

Implementation order:

1. Expose a narrow native DevelopmentDraftHost object. Bind it to the real ProductCore and a persistent local namespace; retain a distinct live Service lease. Explicit creation initializes storage; restore never creates. Revoke leaked handles on scope/disconnect/destruction. Current account support is local only (None), not a pretend authenticated account.
2. Connect a Service-owned controller through existing ProductScopeRegistry and the private Binder session/epoch checks. UI supplies neither authority nor trusted generation. Same control queue checks generation before every mutation; changing scope invalidates handles and original unconfirmed plans. Add actual controller/JVM and Rust bridge tests before calling the route complete.
3. Add a development draft page using the existing shell, manual editing, durable save/restore, full project-plan review and a separate visible confirmation. Unknown results only query the original identity. Keep Requirement/Bug items draft-only. Verify actual Android main/unit/instrumentation compilation and lint separately from runtime and visual acceptance.
4. Register a named development draft proposal tool only in an explicitly selected development chat catalog. Model arguments contain project_name plus bounded kind/text items; the host supplies all source/message/item identities from the original immutable request. Preview before accepting; preserve manual edits.
5. Fix the original proposal acceptance record before saving the exact envelope to DraftStore. Reconcile the same original save intent after failure; never reconstruct a new apply from current draft state. Consume accepted/rejected tool calls locally through existing tool_consumed state, without an automatic remote followup or fabricated assistant answer. Old epoch/session proposal bindings cannot be reauthorized by a new Binder.
6. Run scripted response -> original owner settlement -> source-bound proposal -> preview -> explicit accept -> durable save -> restart/recovery tests, plus wrong scope/old handles/manual conflicts/repeated acceptance and cross-store failure points. Then re-run hosted CI on the final candidate.

Independent architecture review requires explicit namespace/incarnation identity, a fixed cross-store acceptance protocol, terminal tool consumption, old-binding query-only recovery and a single lock order. These are implementation contracts, not requests for user approval.

Current progress: the local candidate now includes nativeDevelopmentDraftHost and UniFFI wiring, Service/controller integration, the development UI, and an explicitly restricted development_draft_propose catalog with source-bound local acceptance, cross-database freeze/acknowledgement and recovery. Eight FFI tests, seven core-agent development tests, and targeted controller/UI checks have been reported passing. The final workspace checks, Android Gradle compilation/tests and lint remain pending the root agent's final evidence.

Architecture follow-up covers stale scope_generation ABA reuse, exact review-plan identity and binding digest, preserving the original command when select_saved uses that same command, and explicit cancellation of the original request for not_saved. The latter two UI changes are still being completed and require fresh targeted verification. Do not mark the final UI candidate complete before those results arrive.

The production budget gate remains fail-closed: productionBudgetProofUnavailable blocks sending. No real model request was made in this implementation or its scripted tests. A scripted proposal/accept/save route proves the local integration only; real provider chat, production authorization execution and production-budget proof remain separate acceptance work.

Real provider calls, OAuth/WebHook synchronization, Reader/FD, physical Android devices and full visual approval stay separate. No local or hosted compiler result substitutes for them. PR108 remains untouched and visually unaccepted.
