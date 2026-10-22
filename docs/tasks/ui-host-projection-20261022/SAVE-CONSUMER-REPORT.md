# Local save consumer preparation — no guessed native API

On6d61baf709f6d5a1e411ec6f24a19f357dc9a8bc, parent assigned a separate Rust owner
for the actual SQLite provider/private local_draft_* facade. This batch only adds
HostDraftSaveState.kt and its dedicated executable tests; no Rust, Runtime, Service,
wire parser or shell file is changed. It does not enable product save.

Backend-independent normalized types model a trusted registered local_workspace
record, an actual live view lease, prepared canonical export and original local-save
receipt. These are local Kotlin names, not a guess about the pending facade JSON.
The future adapter must validate the released native schema before constructing them.
A serialized save captures the actual reducer instance and stable draft identity,
registry generation/stored cursor, canonical memory revision and local view revision.
Archive bytes come only from fixed BotSetupDraft.exportDraft and are copied at the
boundary; output mutation cannot alter the retained original. The new attempt UUID
is a genuine local save attempt, not business/execution identity.

Repeated/pending/unknown prepare returns the same original export/attempt without
new export or dispatch. A receipt must exactly match namespace, scope, draft,
registry generation, original attempt, stored version, memory version and digest.
Wrong/late unrelated data is refused. A committed original advances the known stored
cursor but saved requires the same live reducer object, exact lease and unchanged
canonical/local revisions. Pending/unknown creation remains frozen and its original
creation intent is never cleared by a local save receipt. Duplicate history A cannot
clear newer pending B. Foreign views expose no saved/canSave/attempt/stored version.
MAX and non-editing lifecycle refuse save preparation. No receipt is a grant.

Verification actually executed:
- Test-first missing-source/API RED exit1, full save-consumer-red.log.
- Current actual canonical Kotlin+consumer runner exit0, save-consumer-green.log.
- Independent non-author review and current rerun exit0,
  save-consumer-independent.log. No new blocker found. No port/backend/store request.
- Checks cover every altered receipt binding field, original/duplicate/unknown,
  changed editing and local view revision, replaced reducer, workspace/project/
  conversation/session/generation, MAX, blocked lifecycle, original unknown creation
  preservation, and explicit canonical restore resetting revision/choices/suggestion/
  creation state while preserving registered ID and editing values.
- Scoped authored whitespace check passes. Android was not rerun for this pure Kotlin
  preparation; existing NOT_RUN/toolchain blocker remains and no Android claim is made.

```sh
KOTLINC=/workspace/host-projection-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/run-save-state.sh
```

Actual SQLite descriptor/receipt parsing, Service call mapping and product save/
restore remain pending the assigned Rust owner's fixed bridge SHA; can_save=false.
No account ID, credential, permissions, native request, real user file, main/develop,
paid/deployment or old unknown accounting changed.
