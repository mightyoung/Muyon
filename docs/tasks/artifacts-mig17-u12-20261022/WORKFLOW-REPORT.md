# MIG17 / U12 continuation — durable saves and project inventory

Source branch: `task/artifacts-workflows-20261022`.
Fixed core dependency: `aec085fafef8aa02f86f2fc60626f168b10f4caa`.
This includes the real explicit historical policy hook at `64017cd4` and the
parent-specified final history/Text/COPY handoff. The new source branch inherits
that fixed dependency unchanged; authorship changes relative to it are confined
to artifacts/** and this task's docs. No manual document/core owner edits.

Prior source `4eec6d164e84d87c74b6bc92f45ecb1e3138f680` remains on its original
remote branch unchanged. Its report/review/logs are historical first-batch
records, not verification of this continuation.

## Public integration API

```text
initialize_artifacts_trusted()
initialize_artifact_workflows_trusted()
issue_artifact_project_grant_trusted(project_access, operations, expiry_ms)
revoke_artifact_project_grant_trusted(project_access)
submit_artifact_save_trusted(intent_id, project_access, operation,
                             current_output_access, current_source_accesses)
lookup_artifact_save(intent_id, project_access)
discover_project_artifacts(project_access, exclusive_after_artifact_id, limit)
read_artifact_revision(id, revision, current_output_access, current_source_accesses)
artifact_history(id, exclusive_before_revision, limit,
                 current_output_access, current_source_accesses)
```

`ArtifactSaveOperation` is Archive (artifact_id, origin) or Revise (artifact_id,
expected_artifact_revision, real FinishedBlob, title, origin). Canonical document
creation/upload stays with the existing BusinessStore/document/blob owner.

The former journal-free archive/revise public functions are now cfg(test)-only
internal wrappers over actual in-transaction helpers. Production saving goes
through submit and its journal; the helpers are not publicly exported.

`ArtifactProjectAccess` is not deserializable. It binds existing Scope and
AuthorityBinding plus authenticated actor and exact project revision. Host-only
issuing must derive current actor/membership/purpose permissions from real host
policy, not model-supplied roles, choices or permission lists. All subsequent
uses check the actual persisted grant and live project, epoch, generation,
expiry and purpose in the same transaction. No host dispatcher is added here.

## New same-store table scope

Explicit initialization adds a separate versioned workflow namespace. It does
not migrate or replace existing artifact/document schemas, grants or receipts:

| Table | Owns |
|---|---|
| artifact_workflow_meta_v1 | Exact workflow schema version and store workspace |
| artifact_project_grants_v1 | Narrow project+actor permissions, project revision, grant epoch/generation, <=30s expiry and active state |
| artifact_save_intents_v1 | Original semantic request/digest, actor/project, durable pending, original committed receipt or definite rejection |

All are on the existing BusinessStore connection, BEGIN IMMEDIATE queue and
owner lock. No separate database/connection, document body, blob, source index,
or duplicate document grant truth. Partial/unknown schemas fail closed.

## Real save and Unknown recovery

1. Bind original intent to exact operation, scope, actor, project revision,
   output DocumentRef, source DocumentRefs, origin, expected artifact CAS and
   upload/title for revisions. Hash a versioned serialized request. A changed
   semantic request using the same intent returns IntentConflict.
2. Authenticate project Save, output ReadText+StructuredEdit and source ReadText;
   commit a pending journal row before any document/artifact effect.
3. Publish canonical document/blob, artifact CAS + immutable revision and original
   committed receipt in one existing-store transaction. Tail checks remain live.
4. A duplicate pending/committed/rejected intent returns its existing projection;
   it never executes the effect closure again, including after restart.
5. Storage errors/corruption yield Unknown + QueryOriginal. No loop, automatic
   replay, automatic replacement intent, mark-failed guess, or pending cleanup.
   Lookup of a missing original row remains Unknown/NotFound and creates nothing.
6. A semantic effect failure is definite Rejected only if its terminal journal
   UPDATE changes exactly one pending row and commits. If that write fails or
   changes zero rows, return Unknown, never a fabricated durable rejection.

A failure before pending persistence may leave no row and no business effect;
its Unknown still requires original lookup, never automatic resubmission. A
physical database failure cannot guarantee that a pending marker was persisted.
The host must preserve original intent/request and QueryOriginal behavior.

Receipts deliberately contain only original intent/digest, actor/project,
artifact/document IDs and revisions. No body/title/source snapshots are exposed.
They are historical operation results, not current document state or read grants.
Own-receipt queries require LookupOwnSaves and filter actor/project inside SQL;
another actor's intent and an absent intent produce the same Unknown/NotFound.

## Independent project inventory permission

Discover, Save and LookupOwnSaves are separate project purposes. A valid document
grant does not grant any of them. Discover does not authorize saving, source/body
reading, historical reading or another actor's journal. LookupOwnSaves does not
imply Discover. The issuer must obtain real project-membership policy from the
host; this source does not claim that host integration has been completed.

Catalog output is bounded inventory only: artifact ID/revision, canonical frozen
output DocumentRef/title and human-edit flag. No source snapshots, body or author
history. Stable artifact-ID pagination is project scoped. The title/reference is
explicitly the artifact inventory snapshot, not a claim to be the latest external
document head. Document content requires separate exact/historical permissions.
Revocation/expiry/generation/epoch/project-revision changes invalidate access.

## Exact historical source and output policy

Reads now consume the real core-owned
`document_history_access_in_transaction(tx,current,historical,required)` for
output and each frozen source, comparing returned canonical metadata exactly.
No publication-tail hook is used to read history. No artifact read automatically
initializes or issues historical policy. Current==historical needs ordinary
current authority; older refs require explicit host-issued core policy. A denied
item fails its whole page; source snapshots never follow latest silently.

Revision save preserves all original source snapshots and rechecks their exact
historical permissions at publication tail. Output uses the existing dedicated
publication-tail grant check solely for the write it just performed. Sticky
human-edit protection is retained; new generated content cannot overwrite a
human-edited artifact even with a fresh expected revision.

This is metadata recovery, not a historical byte lease, engine/read capability,
head restore or automatic historical-policy renewal. Actual byte delivery must
recheck appropriate authority at use. Text enum availability is not format or
UTF-8 detection; this artifact catalog does not relabel PDF/Text or parse bytes.

## Evidence and remaining integration

There are 15 synthetic real-BusinessStore test source cases (six initial, nine
workflow/history). Targeted Rust test attempts, full workspace and formatter
attempts remain **NOT_RUN, shell127, cargo/rustc/rustfmt absent**. No installation
or dependency download was attempted, and no Rust test is reported as passing.

The disposable `verify_offline.py` harness imports all tracked fixtures and this
module, adds artifacts export only in that temporary copy, then runs targeted
Rust tests, full Rust workspace tests and formatter check. The real lib.rs is
unchanged. Designated Leader B should apply the core's export patch only after
all modules exist on the combination branch, then execute actual combined Rust
checks in the already authorized tool environment.

Independent SQL execution passed actual extracted DDL/query tests on temporary
disk databases: workflow schema, project grant exact SQL binding/revocation,
durable pending across reopen, failed-effect rollback retaining pending,
effect+original receipt atomicity, conditional terminal row counts, actor/project
lookup filtering, project/cursor catalog bounds and explicit core historical
policy SQL binding. These are SQL tests only; Rust timing, digest validation,
authorization calls and dispatcher behavior remain NOT_RUN/static review.

Final independent review is in WORKFLOW-INDEPENDENT-REVIEW.md. Prior failures,
NOT_RUN evidence and the first review's historical-authorization finding remain
in the repository. Whitespace and Python source parsing checks pass; these do
not substitute for compiler/type checking or the actual 15 behavioral tests.

Remaining: B's module-export/combination compilation and tests; host identity/
membership issuance and UI/FFI wiring; authoritative byte-delivery checks; actual
Android/device/engine acceptance. Ordinary forms/reactions are not implemented
by this journal and must use their real business owner. No whole-product/U12
completion or engine isolation HOLD bypass is claimed.

No original unknown/reservation, user real file, real model/search request,
main/develop, deployment, paid configuration, credential or permission expansion
was touched. The project permissions are a narrow persisted local trusted-host
boundary, not an authorization to broaden actual user privileges.
