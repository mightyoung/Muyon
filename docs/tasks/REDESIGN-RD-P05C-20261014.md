# RD-P05C — actual Kotlin/JVM local-process bridge

Owner: delegated device_deferred_android_mock; sole develop integrator remains B.
Worktree `/workspace/Muyon-device-deferred-jvm-adapter-20261014`, branch
`task/device-deferred-jvm-adapter-20261014`. Original base2646420 advanced only by
FF to B's shared contract/fixtures final head
`b62980bbc91bbc78c0b765118d2221ffd536f45e`. Own writes limited to jvm-adapter/
and this task. Rust, predecessor Presenter, product, root contract and fixtures
remain read-only; active writers retained.

## Actual deliverable

Transport-only stdlib JSON codec and fixed ProcessBuilder RustCorePort, a separate
projection/receipt consumer, stable original-command controller, real process
tests, build/test scripts and input-only driver. Calls actual Rust domain/reducer
kernel, not a mock port or expected-response script. No Kotlin trim/NFC/CAS/
business revision increment, new model round or fake receipt generation.

Commands are in jvm-adapter/README.md. Driver artifact:
`/tmp/rd-p05-jvm-output/rd-p05-driver.jar`; accepts --input sharedscenario --output
externalreport. It emits only actual validated replies and causal plan references.

## Verification evidence

Codec actual assertion RED 0/6 → GREEN6. Projection assertion RED 0/5 → GREEN5.
Real Rust process/controller RED1 passed/5 failed, exit1 (not unavailable binary)
→ GREEN6, extended complete actual suite12 passed/0 failed. Current scoped suite
is 6 codec + 5 projection + 12 actualprocess tests, no skip. Actual covers read,
full raw/NFC core behavior, XML-before-trim and surrogate rejection, max-u64 exact
counter, scope rejection, CAS competing draft, original receipt/dedup/change binding,
lost response/unknown/read-only lookup zero extra effect, missing lookup unknown,
stale actual receipt/epoch independent from newer projection, malformed/null shape.

Shared input-only driver actual results: baseline13, lostreply8, stale-receipt8 =
29 Rust replies. They are post-execution observations, not precomputed expected
outputs. B independently compares Node/JVM/Rust outputs and business properties;
this author's driver run alone does not certify cross-client equivalence.

Tested core binary SHA256:
`eb697e57d445f2b437bd16877177be56a6c5d6b8c9dc5ee9f2f205597e8efa40`.
Core source candidate/final fixed SHA belongs to core writer/B; this task does not
claim non-author acceptance of the dependency. Actual tests use existing fixed
Kotlin2.2.20/TemurinJDK17. Original logs are outside git under
`/workspace/reports/rd-p05c-jvm-20261014/`; jars/private output under
`/tmp/rd-p05-jvm-output`. No binaries/cache/raw logs/secrets are committed.

## Explicit limits and next gates

Local ProcessBuilder/JVM execution is not Android library loading or native device
acceptance. Android actual load/Compose compile/render are **NOT_RUN**;
M03 **blocked_contract**. Durable restart/revocation/real permission/grants/production
native schema, broader keyboard/accessibility and release/device gates remain.
Generic unknown/reply_limit preserves original ownership; no extra retry follows
snapshot/lookup. Core owner's reply-budget stress fixtures are outside this
adapter's finite two-seed actual suite. No new dependencies/licences/account/
credentials/paid/models/user store/device/security/deployment actions.

This writer commits/pushes only its task branch [skip ci]. Non-author immutable
review and B's combined actual regression/exact candidate CI precede any develop
merge; no main/develop merge by this writer.

## Fixed dependency and negative verification follow-up

Core writer fixed remote candidate `37848f123d2a51f7fb0c7af2b28837bd6ba66a5f`;
reported src/main.rs SHA256
`d56307a404aa93978505dde8e75ee66d8769973f2356d6d8b74ca37a32341081`
corresponds to the tested binary above. Source identity is recorded here; core
non-author review and inclusion remain B's responsibility.

Four independent inverse copies compile then fail at expected assertions (exit1):
read clears unresolved ownership; stale display admission allowed; genuine receipt
ledger insertion removed; client raw.trim() applied before Rust. Mutants run under
private /tmp output and do not replace the trusted core binary or original Kotlin
sources. mutation-proof.json records before/after source equality. The complete
restored 6+5+12 scoped suite is rerun before commit; git diff checks cover only the
owned lab/task files.

## Non-author blocking correction at 5c0fcc0

Non-author actual negative evidence (compile0/java1, 0 passed/4 failed) was
reproduced in the author suite before correction: committed with missing receipt;
unknown carrying receipt; sanitized invalid_request carrying data; wrong digest
ledger0 but statuscommitted. These are now strict decoder/projection rejections.
Committed requires receipt; unknown/rejected/conflict cannot claim a receipt;
prepared requires plan/no receipt; hello/snapshot require snapshot/no receipt.
Sanitized empty correlation is admitted only with all snapshot/plan/receipt null.
Presentation only sets committed for an actually bound synthetic receipt; invalid
binding remains unknown/ledger0. Genuine stale receipts still account independently
before current-display gates. No Kotlin result-revision arithmetic/business rule added.

Four original review assertions GREEN4; strengthened validation suite GREEN7 adds
independent sanitized snapshot/plan rejection, allowed verified receipt with null
snapshot (no invented projection), and reply_limit unknown/no receipt projection.
All original23 tests retained: restored complete **6+5+12+7=30 passed**, zero failed
or skipped. Three temporary inverse copies (kind-payload checks disabled, sanitized
data allowed, unbound committed status restored) compile0 and fail at assertions
exit1; original source hashes before/after equal. Fresh three driver actual outputs
remain13/8/8 replies. Raw logs in the external `fix/` subdirectory only.

### Temporary diagnostic collision correction

Original ActualTest and Driver hardcoded stderr beneath
`/tmp/rd-p05-jvm-output`. B's earlier run with RD_P05_OUTPUT pointing elsewhere may
have overwritten the shared temporary actual-core-stderr.log. This is explicitly
**not** a claim that all temporary artifacts were untouched; author source and
external report evidence were not changed by that composition run. ActualTest now
uses RD_P05_EVIDENCE_DIR, else RD_P05_OUTPUT, else the documented default. Harness
exports its resolved output. Driver stderr is adjacent to its unique external
report filename. New verification uses an independently owned fix directory;
private diagnostic routing no longer depends on a shared hardcoded test path.

M03 blocked_contract and Compose/Android actual load NOT_RUN remain. No new
installation/licence/device/account/model scope. Final correction requires fixed
head non-author re-review and B candidate checks; author does not self-sign C0.
