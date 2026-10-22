# Actual five-method Service wiring — production acceptance still HOLD

Read exact B next b13af1124ed1b078609a3b36fcf4f56e5ec27567 handoff
`docs/tasks/overall-combination-next-20261022/FIVE-METHOD-HOST-HANDOFF.md` and RESULTS.
Actual generated commit f604f0a56dc5e69874570ba3c4dd2f54ef427594 now inherited.
Provider is7bb89a713c0ce5678a8c4cae7fc5e24612d88362, not old scalar098d.

## Implemented callsite and exact dependency composition

ProductService.prepare now actually constructs the REAL generated
LocalDraftPrepareRequest using all10 named fields from the same captured
PreparedLocalSave, and calls ProductCore.localDraftPrepareSave(request). The explicit
unavailable placeholder is removed. NATIVE-PREPARE-SERVICE.patch is now APPLIED;
older reports stating it is unapplied or fifth API unavailable are historical.
Four existing native calls stay exact; strict canonical semantics/prepare-before-save/
original-only explicit reconciliation/cold-instance fencing are unchanged.

Conversation/project/namespace/draft/base/generation are the original registered
binding; exportedMemoryRevision and hostEditorRevision remain distinct; archive is
the defensive copy of the exact captured canonical export with next stored revision.
No temporary session generation, account ACL, latest row, fake ID, credential,
creation grant or request/fee ledger is substituted. Lookup may fence prepared state;
ordinary UI reads still never invoke it. No replay from a discovered pointer.

Ordinary dependency merge f89fdd1c4dd328dfddca82fd30f2dd4a015e642a brings B next's
already reviewed provider/core/shell/generated source, including passive cold shell
inputf04f4ef through B's owned composition. It does not merge into B/main/develop.
12 old dependency conflicts were resolved to exact immutable B bytes, not manually
repairing native logic or overwriting user edits (working tree was clean beforehand).
Automatic merge placed bot_drafts export twice; current source restores B's exact
core/lib.rs, removing only the duplicate inherited export. All crates now compare
BYTE-IDENTICAL to B b13af112, including core/lib.rs. No native owner logic was edited.
Inherited MainActivity/ChatScreen/UI changes are source-author dependency history,
not authored UI edits by this Host thread. Sole owners and Leader B merge role remain.

Generated binding matches f604 exactly, sha256:
`e406384f87abe0caac6455b1786b619c123718d94ebf7f91d077a5e229fec0a4`.
Actual generated signature is localDraftPrepareSave(request: LocalDraftPrepareRequest):String.
Every constructor label/type checked against the actual record; no handwritten
record, old scalar ABI, JNI shim or generated-file manual change. Raw static match
in evidence/five-method-binding-match.log, explicitly not compiler proof.

## Verification, with boundaries kept separate

Existing task tools: real Kotlin2.2.20/org.json20250517. Actual commands here:

```
export KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc
export JSON_JAR=/workspace/host-projection-tools/json.jar
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-native-session.sh
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
bash apps/muyon_android/gradlew --offline :app:compileDebugKotlin
cargo test --locked --offline --manifest-path crates/Cargo.toml -p muyon-android-ffi --lib local_draft_bridge_tests
```

- Session runner exit0: actual canonical reducer/codec/Runtime consumer, synthetic
  provider boundary; original scope/base/export/editor/attempt, cold pointer, explicit
  fence, refused late save, terminal monotonicity, read pointer race, wrong scope,
  lost prepare/save reply, late editor and equal-counter new-instance cases.
  Raw evidence/five-method-session.log.
- Joint shell runner exit0, all three mains: actual HostSetupController+Runtime,
  request candidate and cold history decoder. Ordinary open/read zero lookup;
  shell closed actions stay closed, storage-only same-CAS observation accepted,
  cold0/0 never saved, terminal reversal/contradictory facts rejected. Fixture-only
  explicit reconciliation is not production dispatch. Raw five-method-shell-joint.log.
- Android build exit2 BEFORE Gradle: existing Gradle8.13 absent. Actual output
  `NOT_RUN: set MUYON_UI_GRADLE to the existing Gradle 8.13 executable.`
  Raw five-method-android-build.log. No APK/Service/type/device/PFD/engine success.
- Local native targeted command exit127 BEFORE compilation: cargo absent in this
  selected environment. Raw five-method-native-local-check.log. This is a local
  environment limitation, not the old B-cache problem and not a native test FAIL.

Actual B upstream evidence is retained in the inherited overall-combination-next
report/logs: its exact native source ran workspace576 executions (includes repeated
source tests), FFI15/provider26 included, zero failures; actual cdylib/UniFFI generation
and repeat match passed. Current native source is exact B bytes. This supports
native dependency acceptance; it is NOT a fresh native run in this environment,
NOT 576 independent cases, and NOT a real Android Service->native invocation.
Synthetic boundary tests above are never substituted for those native tests.

## Remaining gates, not denied actions

Production Service verified=false stays. Missing fifth generation and the explicit
prepare placeholder are CLOSED. Cold provider pointer and consumer are implemented;
no longer call them absent. Still NOT_RUN: complete Android Service compilation,
real generated Android/JNA/native invocation, process/Binder lifecycle on device,
and whole product acceptance. This thread did not install/relocate a restricted SDK,
use Android stubs, bypass prior tool restrictions, dispatch CI, or flip the bool.
Upstream strict quality gates remain HOLD as B records; do not claim whole UI/product
complete or a deployable build from source/API and offline checks.

Reader PFD/URI/annotation original-intent path remains a separate unfinished owner
contract; no fake FD or cached-byte permission is introduced here. No models/search,
real user files, credentials, external requests, payment/deploy, old unknown retry,
reservation mutation, force push, branch deletion or main/develop change.

Final non-author review: no Important. Actual independent session and shell runners
both exit0; raw five-method-{session,shell}-independent.log. Exact generated/native
byte checks five-method-binding-independent.log confirm unchanged B source. These
are scoped offline results, not Android/Service-native acceptance.
