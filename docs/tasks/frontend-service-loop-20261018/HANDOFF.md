# Frontend/service loop bounded handoff — 2026-10-18

## Ownership and actual completion

B06 thread `01a14d88-2a5f-76ac-886c-5feb4a2c40f5` remains the sole integration
executor. No ownership transfer was received in this task. This branch changes only
the two authorized new directories; it does not integrate UI/PIP/OCR candidates or
change production runtime, AIDL, Gradle or UI. The actual chat → private Android
Service → native Rust Agent → isolated trusted tool → streamed business result and
original receipt chain is **NOT_IMPLEMENTED / NOT_RUN by this task**.

Completed within the available ownership: fixed-source inventory, separate private
contract proposal, executable contract oracle with test-first logs, exact production
ownership request and sequenced implementation plan. This is useful pre-integration
work, not delivery of a simulated chat UI as the real loop.

- [Contract proposal](CONTRACT.md)
- [Implementation tasks and exact ownership paths](PLAN.md)
- [Environment and instruction discovery](ENVIRONMENT.txt)
- [PASS/EXPECTED_FAIL/NOT_RUN and fixed-SHA review](VERIFICATION.md)
- Reviewed oracle SHA: `43ddf7c328464f5e7b2e5752d02f7c582e44f30b`; 18/18 PASS.
- Oracle and logs: `experiments/redesign/frontend-service-loop-lab/`

## Next action needed from parent

Receive B06's final immutable SHA, CI disposition, unresolved issues and explicit
stopped-writer confirmation. Then assign the Service/Rust/bridge/state paths in
PLAN.md to one integration owner, and the narrow conversation adapter/UI paths to
its frontend worker after the contract is frozen. Until that transfer, modifying
these existing paths is **pending authorization**, not an attempted or denied edit.
The new adapter files alone cannot complete a production loop without module/entry
wiring in the existing controller and generated bridge.

The primary blockers are:

1. AIDL/start and AgentStartRequest carry only request ID/variant; no chat payload or
   business stream. The old summary ABI intentionally excludes answer/source values.
2. Existing `service_runtime.rs` constructs synthetic `source.db`, offline authority,
   review and endpoint; that route cannot be called the requested real chat loop.
3. C's supplier schema12 readonly implementation is Linux-only and not in the selected
   inventory base. Android source opening and authoritative ScopeResolver/current-policy
   composition remain missing. Existing host authority reference points are
   `apps/muyon/lib/platform/scope_resolver.dart` and
   `apps/muyon/lib/platform/grants/host_scope_authority.dart`; any changes there need
   separate precise ownership from parent. No grant scheme should be invented here.
4. Compose inventory base has minSdk24 and optional native packaging. Required API26,
   both native ABIs and the actual combined UI/Service APK need same-SHA proof.
5. This environment has no Rust/Kotlin/Android/Flutter executables in PATH. JVM and
   Python are present. Platform checks are NOT_RUN; no tools were downloaded.
6. Rust composition has no verified approved profile/endpoint/credential/budget binding.
   The Service-owned resolver, purpose/model authorization, safe credential access and
   final-send gate must exist before a live-model test. No credential request or call made.

## Source and CI evidence

All inventory claims use fixed source; candidate heads were read, not integrated:

- [Required handoff at 10773ba4](https://github.com/mightyoung/Muyon/blob/10773ba4d7849ee745c2859063ac8a45194687a3/docs/tasks/leaderb-next-20261018/NEXT-REAL-LOOP.md)
- [Current private AIDL](https://github.com/mightyoung/Muyon/blob/10773ba4d7849ee745c2859063ac8a45194687a3/experiments/redesign/android-compose-lab/app/src/main/aidl/com/mightyoung/muyon/androidlab/agentipc/IAgentRuntime.aidl)
- [Rust request DTO](https://github.com/mightyoung/Muyon/blob/10773ba4d7849ee745c2859063ac8a45194687a3/experiments/redesign/rust-agent-host-lab/core/src/service_types.rs)
- [Offline composition](https://github.com/mightyoung/Muyon/blob/10773ba4d7849ee745c2859063ac8a45194687a3/experiments/redesign/rust-agent-host-lab/core/src/service_runtime.rs)
- [UI candidate](https://github.com/mightyoung/Muyon/blob/d3572ea5e74996f468952f16b095775f59ea37b3/experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/conversation/ChatPage.kt)
- [C supplier contract](https://github.com/mightyoung/Muyon/blob/fdc9aea120925229aa592c3551efab9b3f67a825/experiments/redesign/rust-agent-host-lab/core/src/supplier_name_contract.json): supplier object schema_version=1; database schema12 is distinct.
- [Existing min26 candidate CI39102166352](https://github.com/mightyoung/Muyon/actions/runs/39102166352): success at `3f3a2368648db5e9767f11adcae4548ac5da2527`, checked read-only. This certifies that candidate only; it does not certify this contract or a combined real loop.

No new CI workflow was added or dispatched: `.github/workflows/**` is outside the
current write allocation. Local logs provide the oracle evidence. Platform/native,
production store/authority and live-model rows remain NOT_RUN regardless of oracle PASS.

## Holds preserved

I04 legacy-state → HTTP → original-state reopen remains
`DENIED_BEFORE_EXECUTION / BLOCKED` from the supplied history. No retry, rewritten
test, split, reroute or delegation of that action occurred. Dependent merges stay
held. No merge to main/develop, force push, branch deletion, deployment, paid action
or credential configuration occurred.
