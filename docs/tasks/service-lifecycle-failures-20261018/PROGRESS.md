# SDD ledger — plan: docs/tasks/service-lifecycle-failures-20261018/PLAN.md

Task 1 pending; Task 2 pending. Base 7f783eb5cadef65720f8788b077858372f419b62.

| Pair/task | Produces/consumes | Preflight finding |
|---|---|---|
| Task1 / Task2 | source + exact workflow / reviewed scoped execution | Reviewer must approve call graph before execution; no overlap writes |
| Task1 | named failure tests / real Service lifetime fix | Contract permits compiled hooks only, no production authority |
| Task2 | reviewed frozen SHA / CI evidence | dedicated lab trigger only; failures preserved |

Ruling: use the clean task-specific lab branch in the supplied checkout rather than creating another checkout — this environment has no other writer and user authorized a new branch; incorrect occupancy would require re-isolation. Remote open PRs and branch refs were checked before edits.

Independent baseline review (service_failure_review) confirmed Rust service_controller.rs service_admission_probe holds shared mutex across actual callback; retire_service needs the same mutex, while current Service onDestroy invokes it synchronously. Required assertion: onDestroy returns before the held callback is released. Existing generated handle admission protects native close while calls are active. Existing owner-close throw retains slot by ordering; preserve it. Uncertain-constructor fixture must enter genuine generated native constructor before fault, no fake controller. Per-variant package isolation avoids resetting permanent retention. Generic Android pull_request workflow's job guard skips this lab/service-* head branch.

Local execution tools: java present, cargo/kotlinc absent. No Rust/Kotlin local test claims; exact-source dedicated CI required after execution-graph approval. No tests executed yet.

Review correction: AgentLivenessRegistry.dispose only unlinks platform registrations; preliminary claim that it synchronously calls native gone during dispose was withdrawn. Connected client coverage remains useful but is not evidence of that nonexistent path. Confirmed root cause is synchronous retireService against probe-held Rust mutex. Evolving source adds retired to Binder denial guard.

Ruling: seven compiled variants (Setup, SetupOwner, Unknown, Owner, Native, Inflight, Ready) isolate permanently retained process roots without reset/retry tricks. If isolation is wrong the scenarios fail or share state; acceptance requires fresh fixed packages and bounded ordering checks. Unknown is post-successful-native-construction/pre-publication fault; Native is pre-native-close-entry fault. Actual foreign constructor/destructor throwing remains NOT_RUN, not inferred from these injections.
