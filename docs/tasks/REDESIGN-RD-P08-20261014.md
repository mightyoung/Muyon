# RD-P08 Operable Supplier Flow Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Execute RED→GREEN in each owned slice and non-author review before integration. Existing user authorization selects parallel disjoint writers and sole Leader B normal integration.

**Goal:** An actual local synthetic supplier list → raw name editing → version conflict → verified original receipt → restart lookup flow, following v1.3.2 D01.1.

**Architecture:** One trusted Node host maps fixed synthetic records onto the unchanged P07 one-shot Rust/SQLite CLI and durably records draft, stable intent and complete binding before dispatch. Desktop and mobile browser views consume host projections. A Kotlin Android screen consumes that same experimental projection/callback contract without implementing business semantics; native execution is NOT_RUN when unavailable.

**Tech Stack:** Existing Node built-ins, unchanged cached Rust binary/SQLite, existing Chromium; existing Kotlin/JVM toolchain. No installs or dependencies.

**Spec:** v1.3.2 D01.1 page handbook and migration trace; docs/contracts/redesign-v1.3.2/{supplier-name-contract,authorization-minimal-contract,recovery-minimal-contract}.md; unchanged P07 CONTRACT. Root-owned operable-supplier-flow/CONTRACT.md is the experimental UI boundary, not M03.

## Global Constraints

- Exact baseline9524d05ea5d7eff23ea91a7b9f07160c2a8eca0f; preceding P06/P07 are closed dependencies, no repeated whole suites or old OC/CR.
- New files only in experiments/redesign/device-deferred/operable-supplier-flow and owned task reports. No product/schema/CI/old lab edits.
- All data synthetic and in private temporary directories. Fixed S1/S2 identities, same-name fixture, known local binary and private DB; renderer cannot supply process/path/SQL/domain/binding/faults.
- One business implementation: raw UTF16 goes unchanged to P07; normalize/CAS/idempotency/receipt verification stay Rust. Host only orchestrates and projects actual replies.
- P07 preview is validation, not issued authority. Experimental host-assigned plan/candidate bindings and trusted harness action are labeled honestly. No formal grant/mode implementation; M03 blocked_contract.
- Receipt is original P07 content, not fabricated receiptId/cursor. Current row differs from historical committed receipt. New edit/retry cannot automatically replace unknown intent.
- Browser writes restricted to exact loopback Host/Origin, ephemeral same-origin CSRF nonce, JSON/body limits; private host sessions not production authentication. No credentials or external requests.
- Android/Compose/Electron NOT_RUN unless actual appropriate runtime evidence obtained; browser mobile emulation is not Android proof. No devices/models/MUYON_EVAL_REAL, paid resources/install/licenses, main/forcepush/delete/deploy.
- Raw logs/screenshots outside repository. Preserve first failures/all writer worktrees. Disk limited: reuse existing toolchains/targets.

## Review Focus

- Same names for S1/S2 must keep stable ID selection and never update wrong supplier.
- Stale editor CAS must retain original draft and actual current row; no silent revision substitution.
- Double click and lost reply/restart must reuse original binding and lookup only; physical revision/history/receipt count must not increase twice.
- Editing prepared raw input invalidates that prepared binding; in-flight/unknown draft cannot become implicit new intent.
- Malformed/late transport reply cannot create saved status; text rendering and loopback restrictions must resist markup/foreign-origin requests.

## Task 1: Shared trusted host adapter

Owner: host writer ONLY `operable-supplier-flow/host/`, `docs/tasks/REDESIGN-RD-P08A-20261014.md`.
Consumes unchanged P07 read/preview/commit/lookup and installed binary. Produces documented `host/PROJECTION.md` plus `host/flow.mjs`, `host/server.mjs`, own tests/run entry. See parent CONTRACT for API.
- [ ] Write and execute actual adapter RED for name save/restart-original-receipt and CAS conflict against private P07 DB; no compile-only RED.
- [ ] Implement minimal host orchestration and durable session binding, no business logic clone; trusted startup reuses unchanged P07 init containing S1/S2; no host SQL mutation.
- [ ] Test raw invalid input, same IDs/names, preview-only, double submit, stale CAS, actual commit/reply loss and process restart lookup, missing/unavailable lookup fail closed, altered binding, hostile Host/Origin/body/path requests; independently inspect SQLite effect counts.
- [ ] Record GREEN command/exits/counts, first failures, storage/runtime assumptions and limits; commit only owned files, no push/merge.

## Task 2: Desktop + mobile browser page

Owner: desktop writer ONLY `operable-supplier-flow/desktop/`, `docs/tasks/REDESIGN-RD-P08B-20261014.md`.
Consumes host contract, exact JSON projection and action endpoint. No own business mutation/reducer, normalized-name/CAS/receipt authority.
- [ ] Write/run render/event RED using mocked host projection only (clearly distinguish later actual-flow QA).
- [ ] Implement v1.3.2 D01.1: left search, central ID/name/revision list, right current saved value/raw draft/diff/status/receipt; mobile list→detail→full form; accessible labels, keyboard focus, 200% font stacking.
- [ ] Host buttons: select/edit/draft/preview/save/cancel/lookup. Display actual rejected Revision as version conflict while retaining draft/current; bound conflict distinct. Saved only verified committed response. Explicit experimental label and M03 capability limits.
- [ ] Test XSS-safe text, stale/unknown/receipt projections, selection ID and event serialization/double click; no localStorage authoritative success.
- [ ] Commit owned source/tests, report; actual live browser QA occurs after host combination, not claimed from mocked unit tests.

## Task 3: Android source screen + JVM projection checks

Owner: Android writer ONLY `operable-supplier-flow/android/`, `docs/tasks/REDESIGN-RD-P08C-20261014.md`.
Consumes exact shared host projection semantics via an injectable port; do not duplicate raw validation/normalization/CAS/receipt rules or invent JNI/M03 wire. No platform dependency installs.
- [ ] Write/run pure-JVM RED on projection/display/actions: ID, revision text, draft/conflict, original receipt vs current row, unknown lookup action.
- [ ] Implement Kotlin screen model and Compose source page along D01.1 Android addendum list→detail/full editor, cancel unsaved buffer and accessible semantics. Callback port carries host actions, no local business save.
- [ ] Compile/test pure JVM subset with existing toolchain; native screen compilation/launch absent libraries remains explicit NOT_RUN. Report actual operable cross-platform browser mobile QA separately.
- [ ] Commit own source/report only; no build/dependency/permission changes.

## Integration and stopping

Leader B combines exact reviewed commits on latest develop, non-author reviews each task spec+quality and whole branch, independently exercises actual loopback UI with physical SQLite counts and desktop/mobile/200% screenshots using existing Chromium. Root does metadata/reporting, not code/test review. Candidate push triggers existing regression CI; exact terminal success required before ordinary develop PR merge; exact postmerge CI terminal required before final completion. Existing CI does not execute new host/UI/JVM tests.

Stop only dependent scope needing production authority/retention/migration, formal M03 encoding, new dependencies/license/credentials, unavailable tools/capacity or real device/model permission. Keep actual experimental browser flow usable and clearly labeled. Public detailed report rejection must not be bypassed; private Library final delivery allowed. All writers retained.
