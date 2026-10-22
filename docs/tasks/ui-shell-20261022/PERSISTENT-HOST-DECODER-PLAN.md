# Native persistence consumer preparation at9d2c

Fixed source read:9d2c4119d0c66d1748955cee1d86e63deb7ce16f, SERVICE-BINDING-REPORT,
SAVE-CONSUMER-REPORT, actual Service/Runtime/HostLocalDraftSession/NativeLocalDraftCodec/
HostDraftSaveState. This source is not merged into shell while parent review and
cold-start original-attempt index are pending. Production shell/decoder/buttons unchanged.
Actual Service now calls the four generated localDraft methods; missing FFI is no longer
the blocker. Actual Service verified=false remains the release gate, not a missing bridge.

## Actual compatibility check

```bash
python3 docs/tasks/ui-shell-20261022/evidence/verify-host-9d2c-compatibility.py
```

Extracts exact9d2c canonical Bot/archive/runtime/native-codec/session/state sources and its
native session checks, combines the current unchanged shell controller/checks in a task
temp directory, compiles with actual Kotlin2.2.20 -Werror JVM17 and org.json20250517.
Compilation exit0; native-session consumer and shell-controller runners each exit0/PASS.
Full commands/hashes/output: evidence/host-9d2c-compatibility.log.

Fixtures use private synthetic ports; no ProductService/JNI/native database or real model/
search request is executed. This verifies the verified=false memory path remains compatible
and the existing normalized consumer tests work; it does not establish a verified native
release, Android compile, durable process-death original recovery or UI saved-state proof.
Nonauthor reviewer reviewed script/actual logs and the transition risks below; no independent
rerun is claimed for this slice. The prior Android AGP/SDK blockers remain unchanged.

## Exact current projected fields to decode after release

Existing scope, local_draft_id, local_revision, reducer_revision and canonical fields stay
exact. Newly read fields from actual setupProjection:

| Field | Current wire shape | Consumer rule |
|---|---|---|
| persistence_status | unavailable / editing / unknown / saved | Finite values only; no implication of creation/execution |
| persistent_owner_status | unavailable / local_workspace | Local workspace domain, not account identity or authority |
| stored_revision | decimal string or explicit null | Separate stored cursor; never compare it as local memory CAS |
| original_save_attempt_id | actual host UUID or explicit null | Preserve exact original while unknown; never invent or pick latest |
| can_restore | boolean | Must agree with actual supported operations and original-resolution gates |
| saved / can_save | boolean | Keep false until released provider gate and exact host proof are consumable |
| supported_local_operations | finite list adds save / restore / query_original_save | Do not widen the production whitelist early |

Unavailable must coherently retain null stored revision/attempt and false save/restore.
A receipt is storage evidence, never backend creation/permission/cost evidence. Existing
can_create/can_start=false, null business IDs/cost/binding and unavailable metadata remain.
Canonical native revisions are nonnegative bounded signed Long decimal strings in this
provider; do not reuse the reader's unsigned64 revision rules or parse via Double.

## Required controller transition changes, as one tested slice

1. Capture the displayed scope/draft/local revision/reducer revision and all unsent UI
   buffers before explicit save. Keep the host as sole canonical exporter/reducer. The
   generated native receipt parser already binds namespace/workspace/project/conversation/
   draft/registry generation/original attempt/base+next stored revision/exported memory
   revision/archive digest; do not copy that storage reducer into UI.
2. Actual9d2c save/query_original_save do NOT increment local_revision; their response may
   change only projected persistence facts. Current same-CAS whole-snapshot equality must
   be split into immutable editing content versus strictly validated storage observation.
   Do not globally allow same-CAS name/role/step/suggestion edits or drop identity checks.
3. Actual restore increments local host CAS but may reset canonical reducer revision.
   Current reducerRevision monotonic check must have a narrowly explicit restore path,
   bound to the exact trusted stored archive/version and the mounted original identity.
   Ordinary edits and reads retain their prior anti-rollback rules.
4. A committed receipt for exportA may advance known stored cursor even after editingB,
   but cannot mark B saved. Both host canonical memory/local revisions and UI unsent
   name/purpose/role buffers must still match the acknowledged export before the whole
   visible editor can say saved. Otherwise describe only the earlier committed version.
5. Unknown freezes new save, preserves original attempt and permits only exact original
   reconciliation; never replay the export, replace identity, or infer rollback from missing
   reply. Restore/new attempt requires definite prior resolution. Cold re-entry obtains
   original pointer from the durable native index, not receipt timestamp/digest/latest row.
6. Confirm the final index wire/API before implementing query: current9d2c operation accepts
   draftID+localCAS, but exposes original attempt only in snapshot and clears it on commit.
   The final released host must either bind the captured original attempt in the query
   request/reply or prove equivalent original-only routing across terminal/new attempts;
   shell must not silently retarget an old displayed query to a newer attempt. This is
   a coordination request, not an invented extra wire key sent to the strict current API.

## Test-first integration matrix once final index/API arrives

- New fields type/scope/null consistency, unavailable path and unchanged memory behavior.
- Saved receipt exact identity, stored base/next, exported memory/local revision and digest;
  every mismatched binding fails closed, with no false saved label or permission change.
- Same local CAS legitimate storage observation versus same-CAS edited content rejection.
- Save -> unknown -> read original -> original committed/rejected; repeated clicks, old
  query after newer attempt, lost callback and old history cannot acknowledge another editor.
- Edit canonical fields or type unsent UI text during pending save; late receipt acknowledges
  original export only. Reopen/Activity/process/session/scope change uses durable original.
- Explicit restore only: lower reducer revision is permitted with exact trusted archive,
  while unrelated read/edit rollback remains rejected. Dirty buffers require explicit choice.
- No verified release means no save/restore/query IPC or enabled button. Actual Android
  instrumentation/Service/native compilation remain separate acceptance gates.

Ownership: host owner single-writes Service/Runtime/persistence; Rust owner supplies the
fixed durable original index; shell single-writes MainActivity/ChatScreen/ui/shell. Reader
still requires authoritative FD/revision/annotation receipt bridge, never ordinary URI as
permission. No live save, new store, credential, permission/SDK bypass, main/develop merge,
fee/request mutation or paid action is introduced by this preparatory evidence batch.
