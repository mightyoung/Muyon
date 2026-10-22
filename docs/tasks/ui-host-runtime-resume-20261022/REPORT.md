# Host runtime resume — real fifth draft binding

Isolated worktree /workspace/Muyon-host-resume-20261022, branch
task/ui-host-runtime-resume-20261022, BASE214b4031deb38ca7dfd35ee86396089eb48157d5.
Old /workspace/Muyon@97b4d737b01186c73f0c7fa8314aada66d27b868 is preserved;
Claude branches/candidate/main/develop untouched. No merge or deployment performed.
No AGENTS.md found in either tree or workspace (including independent reviewer scan).

The fixed PR101 tree ALREADY contains real Rust local_draft_prepare_save(record)
and generated Kotlin localDraftPrepareSave(LocalDraftPrepareRequest), despite the
stale Service pending error/comments. Generated file is byte-identical f604f0a56dc5e69874570ba3c4dd2f54ef427594,
SHA256e406384f87abe0caac6455b1786b619c123718d94ebf7f91d077a5e229fec0a4.
Only owned ProductService production source changes: actual generated record call,
all10 ORIGINAL captured fields and comments. No new owner/store/gateway/handwritten
binding, no FFI/native/generated source edits. expectedStoredRevision comes from
record.base; next archive revision and exported memory/editor revisions stay distinct.
No prepare retry/latest-export substitution. verified=false explicitly preserved.

Existing HostLocalDraftSession still waits for exact prepare ack before save; query
original is explicit and may fence native prepared attempt, never ordinary open/read.
Cold outcomes remain historical and require separate semantic restore; no old receipt
marks a new editor saved. Gate closure means production UI save/restore/query remain
unavailable; this patch closes a REAL source wiring omission, not release acceptance.

## Fresh verification (this new tree, not old results)

- python3 apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/check-prepare-binding.py:
  static cross-source generated/Rust/Service contract,3/3 PASS incl wrong-base and
  stale-record negative mutations. This is NOT Service Kotlin compile/native call.
- KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc
  JSON_JAR=/workspace/host-projection-tools/json.jar bash
  apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-native-session.sh:
  exit0/PASS. Actual Kotlin2.2.20/-Werror/JVM17, actual reducer/session/Runtime with
  SYNTHETIC private persistence port and forbidden network/business ports. Includes
  loss of prepare/save reply, exact original lookup/fence, restart/restore/late editor,
  crossed scope, malformed ack zero-save, stored0->1 vs memory1/editor42. No native.
- Same environment + run-native-codec.sh: exit0/PASS strict canonical archive/receipt/
  scope/lifecycle/bounds; no backend calls.
- bash apps/muyon_android/gradlew --offline :app:compileDebugKotlin: actual DIRECT
  exit2 NOT_RUN, existing Gradle8.13 missing. Checked PATH/trusted workspace caches;
  Java/Kotlin/org.json available, Rust/Gradle/SDK/JNA absent. No workaround/install,
  privilege expansion, new credentials or paid execution attempted.
- git diff --check: PASS. Independent static review no new Important; reviewer
  independently executed static3/3, session and codec exit0. Raw independent logs
  retained. Reviewed Service SHA256 f06f3f3b4b7817e57a785d9918d067997bad568b3d0437499798579021bf12b5.

Original prepare-contract-red.log fails because Service actual call absent. Initial
checker bootstrap IndexError is separately preserved prepare-contract-bootstrap-error.log,
not represented as product RED. All fresh raw outputs are under evidence/.

## Reader facts and exact pending interfaces

Reader latest examined source: Corebe90295872885b499cc88e983d9146542e0033e2,
crates/muyon-core/src/documents/reading_policy/{mod,types,store}.rs; observe/begin/
prepare/renew and native selection/frame hooks exist. D renew source is follow-up
UNCOMPILED/NOT_RUN, not completion of seven APIs. E reconcile/F stop/G genuine ticket
handoff and approved initial authorization are still pending per checkpoint/source.
Do not represent earlier header A/B/C as proof D absent or D source as native PASS.
FFI source1c64ab50021c6183f281ee32f751f2a2876a4e45 explicitly requests concrete core
facade in docs/tasks/reader-evidence-ffi-20261022/CORE-READER-POLICY-ATOMIC-REQUEST.md;
there are no real generated seven policy endpoints to consume. Fixed214b Kotlin
binding also has NO documentPresentation/documentRead/policy methods. Do not import
97b NativePort into this tree and fake its missing ABI, substitute attachment cache,
or reimplement policy SQL/owner in Host. Existing own97b controller can be hardened
independently on its proper source graph; its backend remains unavailable.

Exact owner work needed: native reconcile(scope/originalAttempt/kind; may fence),
stop(original retained owner/root, no live-scope prerequisite), continue_presentation
(original renew/token/predecessor/actual new ticket), initial explicit-selection
admission plus persistent document-deny/version, selection/frame/revoke integration;
then FFI concrete records/signatures and actual matching generated binding. See
97b's NATIVE-READER-POLICY-V1.md / FIRST-READ-APPROVED.md for approved semantics,
not implemented APIs. No second gateway/store or fake allow added.

No real user file, model/search request, old unknown retry/fee mutation, account ACL,
permission expansion, main/develop/PR101 candidate update, merge, forcepush/deletion,
deploy or payment. Android/native whole Host acceptance remains pending, not denied.
