# Native local-draft consumer checkpoint

Fixed interface baseline: local-workspace provider7ca2bd4e9edf9cd0952ce784d3f85561583537db.
Read fixed-source3160208247c5257b6382106d69f2028f5ad8ccab NULL-PROJECTION-FIX.md:
public interface unchanged; actual parent Rust re-verification still pending.
Canonical Bot archive dependency53b9b597e190db6b6619a18e8746f2985f488fbc is already inherited.

Implemented source: strict NativeLocalDraftCodec, HostLocalDraftSession, Runtime
consumer and private typed Service boundary. Independent review caught that this
branch's generated bindings do not yet declare the four native methods; verified=false
cannot prevent a compiler error for absent symbols. Production Service therefore
explicitly throws unavailable for this disabled adapter. The exact four-method
callsite patch NATIVE-SERVICE-ADAPTER.patch is reviewable but unapplied, pending
fixed provider + actual generated binding composition. No reflection/dynamic shim.
Service deliberately has verified=false: parent independent native evidence
fda22f1876393b390e73591ffbf5991e686c8ef6 found first resolve fails (14/15 tests).
No production persistence was enabled or exercised. No FFI/lib.rs change here.

Codec requires exact schema/keys/types/local_workspace/live scope/UUID/decimal
Long bounds/editing_only; account-like fields are refused. Read verifies full
canonical semantic archive, digest and stored revision. Save exports next STORED
revision (example memory revision3 -> stored revision1); exported memory/local
editor revisions remain separate original receipt bindings. Unknown/malformed
post-dispatch replies retain original attempt/export, disable another save/restore,
and allow only original lookup. Recovery never substitutes latest editor or row.
Late original receipt advances storage cursor without marking newer editor saved.
Restore explicitly resets runtime authority through canonical API; newly reopened
existing archive requires restore before saving, avoiding blank overwrite.

## Shell consumer protocol

Existing chat_setup_draft stays schema_version1, additive fields:
- persistent_owner_status = local_workspace only with verified real provider;
- persistence_status = unavailable/editing/unknown/saved;
- stored_revision decimal String or null; original_save_attempt_id UUID or null;
- can_restore Boolean; saved/can_save reflect exact current editor;
- supported_local_operations adds save/restore/query_original_save only when allowed.

Each new operation uses existing {action,local_draft_id,expected_local_revision}
with exact keys. Do not inject namespace/draft owner/attempt/revision fields from
model JSON. Save/query do not change editor CAS; duplicate confirmed save is
unavailable, and Unknown offers query_original_save. Restore increments editor CAS. A thrown/malformed save or rejected original lookup
returns unavailable/setup_save_unknown without name/purpose/role; it retains the
original binding and offers recovery_action=query_original_save plus local draft ID
and expected local revision. It never displays old editor data after scope rejection.
Persistent open/read/edit revalidates native current scope/registry (or exact original
lookup while pending); it does not return a stale business snapshot on rejection.
Service currently advertises none of these new operations because verified=false.
Creation/start remain disabled with no native grants or business intent.
Workspace+live project is local ownership, not account ACL or conversation grant.
Conversation is the current private app UI's UUID; UUID parsing confers no authority.

## Concrete remaining blockers

1. Parent/sole Rust owner fixes provider first resolve and verifies actual native
   combination/export, generated bindings and Service compilation. No parallel Rust fix.
2. Original attempt/export currently survives only the mounted process. Provider
   persists committed receipts, but resolve/read do not expose a durable original
   pending-attempt pointer, and Host has not persisted that pointer. Cold reopen MUST
   NOT claim original-unknown reconciliation, infer original from latest receipt,
   or enable production save until this is addressed. Suggested exact coordination:
   persist a pre-dispatch local save attempt binding (namespace/draft/generation/base
   stored rev/attempt/exported memory+editor revisions/digest) and recover that exact
   binding before any subsequent save. This is LOCAL save bookkeeping, never an
   execution/create grant or historical request ledger. Native same-store pending
   registry is preferred to a second uncoordinated file transaction. Sole Rust owner
   must fix/release contract before we wire it; do not guess new method signatures.
3. Actual Android Gradle/SDK/generated bindings/PFD acceptance remains NOT_RUN;
   recorded environment restriction is not bypassed.

## Reproduction and evidence

Use actual Kotlin2.2.20 and org.json20250517, no Android/generated stubs:

```
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc
JSON_JAR=/workspace/host-projection-tools/json.jar
export KOTLINC JSON_JAR
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-native-codec.sh
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-native-session.sh
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
```

Raw outputs: evidence/native-codec-green.log, native-session-green.log,
native-runtime-regression.log. Runtime test-first output native-runtime-red.log
records missing constructor port before implementation; codec/session source and
its initial tests were authored together (no fabricated test-first claim there).
Native session covers verified gate, revisions3vs1, lost reply after synthetic
commit, repeat only lookup, late edit, restart/canonical restore, wrong scope,
Runtime real queue/CAS/unsupported duplicate/stale generation/cancel.
No real model/search/user files/network business request was made.

## Independent review follow-up

Non-author review found missing generated Service methods and inconsistent
archive-present/stored-revision combinations; both corrected. Native descriptor
regression was executed RED before correction (native-descriptor-red.log).
Review then identified swallowed scope rejection in unknown lookup, exposing the
old editor. Added native-revocation-red.log before fixing save/query failures to
retain original outcome but return unavailable without editor content. Final tests
include lost reply + revoked project + original lookup + same attempt + no new save.
Reader native request is READER-FFI-MINIMAL-SCHEMA.md; canonical StoreEvidence byte
flow read at78cdff32dee68b664c4fe71b4bbd6b81251af5e7, no cache authority substitution.

Final non-author re-review: all three current runners exit0, no remaining Important.
Raw evidence/native-{codec,session,runtime}-independent-final.log retained. Independent
scope reproduction before fix returned local_only/has-name=true/save-count=1;
after fix unavailable/has-name=false/save-count=1. Both original outputs retained
in native-scope-independent-{red,fixed}.log. This is real JVM source verification,
not native-provider/Android acceptance. Current actual Android compile command
`bash apps/muyon_android/gradlew --offline :app:compileDebugKotlin` exits2 with
NOT_RUN: set MUYON_UI_GRADLE to existing Gradle8.13 executable. Raw output retained
in native-android-not-run.log. No restriction was bypassed.

## Latest fixed-provider Rust verification (supersedes pending Rust status above)

Fetched/read evidence dc7f1c0c5331c5ecb53e4dfa33c0c0cb3d6b7bfa,
NULL-FIX-RUST-RECHECK.md. Exact tested combo f0ef760ba7253f38be8e26989ca99b82a76acf8b
is owner3160208247c5257b6382106d69f2028f5ad8ccab plus sole core module export,
no provider behavioral edits: actual provider19/19, core202 (includes those19),
scoped rustfmt exit0. The original NULL failure is CLOSED for that Rust combination;
old RED is historical evidence, not a current blocker. FFI was not newly executed
because of known offline anyhow cache gap; generated Android bindings/Service compile,
durable cold-process original-attempt binding and Android acceptance remain pending.
Production verified=false remains accurate for these remaining gates. Service comment
updated accordingly; no new failed-Rust claim or retry of the resolved issue.
