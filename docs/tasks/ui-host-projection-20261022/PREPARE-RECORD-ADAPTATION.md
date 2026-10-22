# Provider7bb89 typed prepare request adaptation

Read fixed7bb89a713c0ce5678a8c4cae7fc5e24612d88362 INTERFACES.md and actual FFI
LocalDraftPrepareRequest definition/local_draft_prepare_save body. The four existing
methods and strict preparation/descriptor/outcome JSON are unchanged. ONLY new
prepare ABI is now one actual UniFFI record; old098 scalar prepare list is obsolete.
No local/generated record is handwritten as a replacement.

Host's private port now receives the existing immutable captured PreparedLocalSave
object, rather than flattening/reordering10 parameters. Session passes the SAME
original export to prepare, checks exact acknowledgement, then uses its original
archive/attempt for save. Existing cold original/fence/terminal/history rules stay.

Service intentionally still has explicit unavailable prepare and verified=false,
with no reference to a missing generated class. Updated NATIVE-PREPARE-SERVICE.patch
is UNAPPLIED. It constructs the future REAL generated LocalDraftPrepareRequest
using named fields and calls localDraftPrepareSave(request), not scalar ABI.
Kotlin generated field spelling/record constructor still MUST be checked against
B's actual accepted generation before applying; the patch is a contract mapping,
not proof that generated fifth binding compiled or was consumed.

Exact mapping from provider record fields to captured original:

| Native record field | Existing captured value |
| --- | --- |
| conversation | original.record.conversationId |
| project | original.record.projectId, preserving null |
| namespace_id | original.record.namespaceId |
| draft_id | original.record.draftId |
| expected_generation | original.record.registryGeneration decimal String |
| expected_stored_revision | original.record.storedRevision decimal String (BASE) |
| attempt_id | original.attemptId |
| exported_memory_revision | original.exportedMemoryRevision decimal String |
| host_editor_revision | original.exportedLocalRevision decimal String |
| archive | original.archive defensive byte copy, canonical NEXT stored revision |

Temporary session/generation is never substituted for the registry generation;
proposed next archive revision is never substituted for base CAS or editor revision.
No account ACL, extra grant, creation intent, credentials, model call or filesystem
journal is introduced. Reader FD/URI/annotation bridge remains separate pending
fixed native/reader contracts; no fake reader descriptor is returned.

## Actual verification

Test-first evidence/native-prepare-record-red.log records old scalar override compile
failure before port adaptation. Updated synthetic port checks actual namespace/draft/
workspace/project/conversation/generation/base/next identity, then all original
cold-recovery/unknown/fence/terminal/late-instance/read-race Runtime tests run.
A distinct-counter case captures memory1/editor42/stored0->1, observes exact prepare
fields and only current editor42 is saved (43 is not). This tests host export/port
mapping, NOT the unavailable generated constructor or Android Service compilation.

```
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc \
JSON_JAR=/workspace/host-projection-tools/json.jar \
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-native-session.sh
```

Actual exit0, raw evidence/native-prepare-record-green.log. Non-author delta review
and actual rerun exit0, raw native-prepare-record-independent.log; no Important,
diff-check0. Unchanged codec/source is not repeatedly tested merely to inflate counts.

Parent reports provider7bb core/tests byte-identical to verified111e. No new fifth
FFI/binding/Android result is inferred from that equality or prior four-method PASS.
Wait for actual B-generated fifth record/method, verify exact signatures and source
SHA, apply reviewed mapping, compose true native source and rerun acceptance before
closing relevant gates. No unconditional verified flip; Android remains NOT_RUN.
