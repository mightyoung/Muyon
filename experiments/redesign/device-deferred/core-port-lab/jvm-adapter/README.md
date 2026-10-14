# RD-P05C actual Kotlin/JVM local-process adapter

This laboratory calls the **actual Rust executable** at the fixed trusted path
`/tmp/rd-p05-core-target/debug/rd-p05-core`. It does not use MockRustCorePort or
script expected responses. It is not JNI/Android loading, a product DTO or M03
schema freeze. Effects use only synthetic startup fixtures.

## Existing toolchain commands

```sh
bash experiments/redesign/device-deferred/core-port-lab/jvm-adapter/run-tests.sh
bash experiments/redesign/device-deferred/core-port-lab/jvm-adapter/build.sh
/tmp/muyon-spike01-toolchain/jdk/jdk-17.0.20.1+1/bin/java \
  -jar /tmp/rd-p05-jvm-output/rd-p05-driver.jar \
  --input experiments/redesign/device-deferred/core-port-lab/fixtures/scenario-baseline.json \
  --output /workspace/reports/rd-p05c-jvm-20261014/actual-baseline.json
```

Repeat driver with scenario-lost-reply.json and scenario-stale-receipt.json.
Driver accepts only input-only scenario/seed/steps format defined by B's
CONTRACT.md. Seed selector maps to the two owned fixture filenames. ProcessBuilder
uses fixed executable plus `--seed` and never a shell. No renderer process/path
capability is exported. Output is restricted to /tmp or /workspace/reports and
contains scenario_id and validated actual Rust replies only; it contains no
client-specific metadata or expected answers. plan_id_from copies the plan.id of
an earlier actual reply, rejecting explicit-plus-reference ambiguity.

Defaults reuse Kotlin2.2.20/JDK17 already installed. RD_P05_KOTLINC,
RD_P05_JAVA_HOME and RD_P05_OUTPUT can select existing local tools/output. Binaries
and raw logs are outside git; no Gradle, JSON library or dependencies are installed.
The actual suite fails with explicit NOT_RUN if the trusted binary is unavailable;
absence is never counted as behavioral RED or success.

## Responsibility boundaries

Json.kt is a bounded-depth codec with duplicate-key/trailing-input rejection;
JSON numeric tokens are never rounded. Request counters remain canonical decimal
u64 strings; raw string maps directly to every original UTF-16 code unit. Kotlin
performs no name trim/NFC, CAS, business revision increments or business receipt
verification/recovery decisions. Those execute in RD-P01/RD-P02 through the Rust
backend. Port.kt reads bounded NDJSON incrementally, strictly decodes UTF-8,
validates response protocol/correlation/shape/counter transport types and closes
on EOF/timeout/invalid responses. Reason-only transport failures never create an
effect receipt.

Controller uses immutable original Business/BoundPlan and remembers sent intents.
Double tap never sends another commit; unknown survives read/reconnect/edit and
requires explicit read-only original lookup. Any unknown, including reply_limit,
keeps ownership and never causes implicit retry/commit. Missing/unreadable lookup
is not evidence of no effect. A successful core lookup may supply a verified
receipt with null snapshot if projection would exceed budget; it accounts the
receipt independently and does not invent a projection.

Presentation binds received synthetic receipts to the original intent/object/
expected revision/core parameters digest and keeps them in an independent ledger.
It only projects same-domain/current-epoch snapshots whose cursor watermark does
not regress. Business result revision is presented as Rust returned it; Kotlin
never calculates expected+1. A stale epoch's genuine receipt may be retained,
while draft/raw and newer display remain unchanged. Snapshots, effect outcome,
display epoch and original intent are distinct axes.

Pure codec/presentation tests use synthetic frames solely for local decoder and
projection properties; these are not Rust execution evidence. ActualTest.kt
launches fresh real Rust processes, validates actual results and controller state,
and observes real ledger/cursor behavior. The three shared driver runs produce
actual replies for B's subsequent independent equivalence comparison.

## Honest remaining gates

Synthetic in-memory ledger is not crash durability or production authorization.
Native adapter policy/grants, account/store credentials, persistent process
restart, broad UI/accessibility, Compose rendering, JNI/device/lib loading and
release gates remain unimplemented/unverified. Reply-budget stress is checked by
the core owner's suite; this adapter's actual runs use the two bounded shared
seeds, with generic unknown handling. Android actual load and Compose are
**NOT_RUN**. M03 is **blocked_contract**. No model, user store, Android runner,
new install/licence/account/paid/security/deployment permission is used.
