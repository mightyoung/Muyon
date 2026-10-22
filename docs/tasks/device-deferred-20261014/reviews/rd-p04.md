# RD-P04 R2 independent fixed-head review

**Bounded C0 for experimental mock-source/Compose-source intake**, fixed `97274f9ff8c4960e5b5ccede4673d2863ae20500` (parent `3e3b29625b1a6594677f73ac9845f15d91d45771`). R1 and R2 findings closed for this mock scope. Integrator still owns combined regression/CI gate before inclusion. No Android/Compose/native/production acceptance or M03 freeze.

Independent git archive `/tmp/rd-p04-independent-r2-review`; JVM output only `/tmp/rd-p04-independent-r2-output`. All six archived files match exact Git blobs after tests/mutations, recorded in blob-proof.json. Delta only Presenter/tests/README/taskdoc, four owned files. Compose/run script unchanged. Reviewer did not modify author worktree, install/accept terms/access device, commit/push/merge or launch browser.

## Actual fresh evidence

Existing Kotlin2.2.20 / Temurin17 compile and full author JVM suite exit0: **38 passed/0 failed** (jvm38.log). Includes all prior32 fixtures and six projection/raw/ledger regressions. Original independent R1 empty/unchanged r4 effect probe freshly compiled0/runs0:2 passed/0 failed. Neither invalid revision enters ledger or marks SAVED. Original independent SnapshotProjectionProbe compiled0/runs0: legitimate original r5 receipt ledger1, current accepted supplier Current/r8 preserved, statusREADY. Strengthened independent raw/intent probe also verifies the entire original Draft unchanged (including whitespace/lone-surrogate raw, intent, expected revision) after that late receipt.

Three reviewer-generated reverse mutants independently compile0 and run with genuine assertion exit1: remove stale receipt display guard37P/1F; remove snapshot object guard36P/2F; discard authentic receipt insertion29P/9F. Each temporary working copy restores original Presenter bytes in finally, all exact-byte comparisons true, archive/source remains pristine. Full names/stdout/exit/restoration in mutants.json and individual logs. No raw log/binary added to Git.

## Scope of the correction

Original registered immutable command/expected revision validation is retained before accounting. Authentic original receipt is stored in original intent ledger before projection decisions. Full command/domain identity plus display generation/object guards precede current-view changes. Same supplier result counter older than accepted current counter cannot replace the projection or raw draft and does not claim SAVED for the newer current state. It remains accounted independently. Snapshots first obey domain/generation/watermark; within that accepted domain, an older same-object mock counter cannot regress current receipt-derived/snapshot-derived state. Event watermark, display epoch, object counter and user intent are separate.

The canonical u64 rN/+1 parsing and same-object comparison are explicitly declared temporary mock conventions. They do not establish authority, provenance, cryptographic identity, production opaque-version ordering or M03 wire encoding. Equal revision/equal watermark payload consistency relies on future trusted atomic-snapshot adapter as already documented. Foreign domains are rejected; source does not compare arbitrary domains as one version sequence. No receipt advances/fabricates an event watermark. Original/new user intent and raw buffer are retained until explicit subsequent edit; this is in-memory behavior, not process restart durability.

## Remaining unchanged gates

Compose SupplierScreen.kt only statically reviewed and excluded from JVM compile. Compose compilation/render/TalkBack/font/rotation/keyboard **NOT_RUN**; Android actual load **NOT_RUN**. M03 **blocked_contract**. Real Rust port, trustworthy scope/purpose/permission/source/effect checks, production ModeGrant/risk rules, durable drafts/commands/receipts, unknown read-only lookup, conflict resolution, read/write revocation and new-stream resync remain required. Decision ALLOW/CONFIRM/HARD_DENY exercises mock routing, not real authorization or UI-generated grant.

## Commands

`RD_P04_OUTPUT=/tmp/rd-p04-independent-r2-output bash /tmp/rd-p04-independent-r2-review/experiments/redesign/device-deferred/android-mock/run-tests.sh` — exit0/38P0F.

For original R1, original R2 and raw/intent extension: existing `/tmp/muyon-spike01-toolchain/kotlin-2.2.20/kotlinc/bin/kotlinc` with `JAVA_HOME=/tmp/muyon-spike01-toolchain/jdk/jdk-17.0.20.1+1`, archive Presenter.kt plus independent probe, flags `-jvm-target 17 -include-runtime -d /tmp/rd-p04-independent-r2-output/<probe>.jar`; same JDK `java -jar` — fresh compile/run0. tests.json and separate compile/run logs preserve outputs.

Mutants: copy archive Presenter bytes to separate `/tmp/rd-p04-independent-r2-mutants/<name>/Presenter.kt`, change exactly one guard/ledger site, compile with unchanged archive tests, run java, restore bytes in finally. Compile0/run1 with named assertion failures, never import or compilation failure.
