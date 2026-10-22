# Draft persistence frame — production integration BLOCKED

Owner facts and required live host seam were published first at
d63d23b2a8c89b3fe253bb9575913d80b301caee in PERSISTENCE-OWNER-CONTRACT.md.
Canonical Bot export/restore API49ad2a8dfe7fe65bad600d985f9e1631252191da was adopted
by dependency merge22fda0c795cbcc01d9a3562c64b0a28073e541f4, preserving its original
test-first commit. Dependency-owned source/tests/evidence in that merge are not
local authorship. No reflection or edits to canonical Bot files.

## Delivered independently useful work

New dedicated chat/persistence/HostDraftStore.kt and synthetic-only JVM tests.
Runtime adds truthful persistent_owner_status/persistence_status unavailable and
stable setup_persistent_owner_unavailable response for save/restore. No disk store
is instantiated by Runtime/Service; no actual app data or previous unknown is read.
Service, ChatScreen, MainActivity, catalog, credentials, Rust documents and billing
remain untouched in this authored delta.

Fixed archive API is the only editing-data serializer/parser. Store validates actual
UUID, strict full bounded JSON envelope, exact stable-owner tuple, schema, digest,
base64/canonical archive and matching stored revision. No partial restore, migration,
corrupt-record reset or unknown-schema fallback. It stores no memory/field revision,
step, scope lease, creation identity/history, permission, fees, capability/material
selection, suggestion token, account grant or credential. Canonical archive contains
only the reviewed edit fields/locks/accepted template provenance and stored revision.

OS file lock and same-JVM lock serialize exact expectedStoredRevision CAS. Existing
record+expected null is a conflict, corruption prevents overwrite, MAX rejects next
without wrapping, frame0 remains valid data. save bounds the archive before copying.
A temporary file is synced before mandatory ATOMIC_MOVE; final directory sync must
succeed before Committed. No non-atomic rename fallback. Pre-publication failure
returns Rejected; publication/durability uncertainty returns Unknown with the exact
attempt version/digest/exportedMemoryRevision. recoverReceipt accepts only that
exact record, never a newer record as an old receipt, and resyncs before confirmation.
Receipt exportedMemoryRevision is ephemeral caller context; it is not persisted.

Root must already exist and be trusted/durable; missing root rejects without mkdir.
Host owns namespace-creation parent fsync. Read/recover require a trusted nullable
minimumStoredRevision floor: null=no prior anchor, nonnull0 is a genuine anchor and
refuses missing data. Known higher floor rejects valid-but-older archive. There is
no claim to defeat malicious full-namespace/anchor rollback or forged valid editing
data: SHA256 detects damage, not authentication/encryption. Future host must supply
real stable owner/record mapping, current authorization and independent rollback
anchor, and check unresolved original creation/stop ledger before restore. It must
bind save callbacks to the same live reducer/scope and exported memory revision;
no production saved flag is enabled without these guards.

## Actual tests and original evidence

- Before implementation, persistence runner compile RED exit1 on missing store
  API/source. Full original persistence-red.log retained.
- Initial minimal-edit prototype passed synthetic tests (persistence-green.log),
  then was replaced by fixed canonical archive before delivery. It is not shipped.
- First canonical integration compile failed from stale parameter type names;
  exact persistence-codec-integration-failure.log retained. Corrected source passed.
- Final canonical runner exit0; persistence-codec-green.log. Tests include restart,
  two actual JVMs racing the same CAS (exactly one commits), disk faults before temp
  write/before move/after move, honest Unknown+exact recovery, later revision refusing
  old receipt, process halt before/after move, wrong owner, corruption refusing both
  read/save, unsupported schema, extra field, trailing garbage/second JSON/raw NUL,
  file/archive size bounds, valid older archive vs trusted higher floor, true anchored0
  missing refusal, valid frame0/MAX and MAX overflow refusal, stable UUID and memory
  revision receipt. All data/root/owners are synthetic in temporary directories.
- Runtime host scope/candidate/setup regression exit0, two PASS lines:
  persistence-runtime-gate.log; save/restore refuse and never call a private port.
- Actual canonical reducer run exit0, 17 checks: persistence-bot17.log.
- Non-author independent final canonical/null-floor runner exit0 and source review:
  persistence-independent.log. Initial strict parse/root durability findings were
  fixed; anchored0 ambiguity fixed with nullable floor. Full review in REVIEW.md.
- Actual Android full-suite wrapper exit2 NOT_RUN, no existing Gradle8.13 in this
  selected environment: persistence-android.log. No SDK retry/relocation/bypass.
  Android compilation, filesystem/device/backup/restore tests are unexecuted. JVM
  process halt is not power-loss durability or Android filesystem proof.

Commands from repository root (real Kotlin2.2.20 and org.json20250517):

```sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc JSON_JAR=/workspace/host-projection-tools/json.jar bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-offline.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc JSON_JAR=/workspace/host-projection-tools/json.jar bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh
```

Android attempt from apps/muyon_android:

```sh
./gradlew --offline --no-daemon --console=plain :app:testDebugUnitTest :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest :app:lintDebug
```

## Exact remaining blocker

Action: enable actual product local Bot save/restore via chat_setup_draft.
Target: persistent stable-account/workspace/project/conversation-owned namespace,
record identity, rollback anchor and original creation/stop guard.
Reason: those trusted persistent mappings/ledgers are absent from current product;
conversation UUID preferences, local-workspace literal and temporary Service leases
cannot establish them. Status: BLOCKED/PENDING contract, not approval denial and
not an attempted production write with uncertain outcome. Completed: tested storage
primitive and explicit canonical codec integration; actual production I/O not begun.
Parent must coordinate the genuine persistent owner/ledger producer before enabling.
Do not implement fake account/installation IDs or reuse an archive to clear unknown.

No actual saved/created Agent, permission restore, backend write or all-UI completion
claim. Historical two unknown/¥0.002620 held remain untouched. No main/develop edit,
merge, force push, deletion, deployment, credentials, paid or real external request.
