# Actual Service failure lifecycle Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development. User already authorized implementation and independent review; no additional plan approval is required.

Goal: verify and repair actual Service setup/cleanup failures and inflight native/onDestroy ownership.
Architecture: retain PR93's real native and durable callback chain; inject faults only via compiled fixture owner/hooks. Prefer a separate compile-time fixture variant if process-lifetime retention prevents sequential scenarios. Test APK must have no INTERNET permission.
Tech Stack: Kotlin Android API26, UniFFI, Rust, SQLite, dedicated GitHub Actions.
Spec: CONTRACT.md beside this plan.

## Global Constraints
All CONTRACT.md boundaries apply. Source changes limited to Service/controller/host lifetime and new fixture/test/workflow/helper packaging paths. UI, Dart, legacy DB and forbidden suites excluded.

## Review Focus
- Acquired owner close throws before native entry: retained slot cannot be reused.
- Native constructor entered then fails: unknown outcome retains lease/slot.
- Native admission callback in flight during actual onDestroy: callback remains valid until native disposal proves quiescence.
- Native cleanup or owner close fails: neither duplicate owner nor false cleaned report.
- onReady failure or construction/destruction race: native controller remains reachable and eventually settled or conservatively retained.

### Task 1: Minimum tests and implementation
Files: actual AgentRuntimeService.kt, GeneratedAgentController.kt, ServiceHostBindings.kt where needed; new compiled fixture Application and named instrumentation test(s), dedicated workflow and bounded packaging helper; build variant only if required. Never modify Compose UI.
Interfaces: preserve real GeneratedAgentController native entry and durable ServiceAdmissionProcessOwner. Any test seam must be compile-time installed from Application and default no-op, with no Binder runtime selector.
- [ ] First write named deterministic test assertions for setup/uncertain constructor/cleanup failure and inflight onDestroy. Capture expected baseline failure when safe, or explain NOT_RUN before workflow review.
- [ ] Implement smallest ownership fix to satisfy contract; no generic refactor.
- [ ] Add exact-branch workflow cloning only audited safe lifecycle producer graph, exact named instrumentation classes, no old workflow dispatch.
- [ ] Self-review transitive execution graph, compile surfaces and failure statuses. Commit source. Write implementation report with precise paths, commands, expected evidence and remaining gaps. Do not push/run CI before independent execution review.

### Task 2: Independent review and scoped execution
- [ ] Fresh read-only reviewer checks full diff, spec/quality/concurrency and exact test/workflow graph including imports. Address findings with original implementer and re-review.
- [ ] LeaderB publishes source to new lab branch, stacked Draft PR targeting PR93; monitor dedicated CI to terminal. Preserve every run and NOT_RUN.
- [ ] Collect bounded direct logs/API metadata only; never retry denied archives. Independent final review maps claims to exact source/results.
- [ ] Commit short results/handoff; stop writers. No merge.
