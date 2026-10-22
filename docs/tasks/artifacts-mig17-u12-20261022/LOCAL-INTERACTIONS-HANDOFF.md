# U06 / U09 typed local storage — source delivery / execution HOLD

Branch: task/artifacts-local-interactions-20261022.
Immutable starting artifact source: de3ec5b56de80f30c5a98c0b22bae64ece6167ae.
Inherited core: aec085fafef8aa02f86f2fc60626f168b10f4caa.
Design read from 400e206135690c284c8402521e3135cfb7bfaee8 U06/U09/U08/U13.
No AGENTS.md/.agents skill files exist in this snapshot/ancestors.

## Existing implementation and exact scope

Kotlin ComponentLedger already handles transient CAS, attempts, pending/unknown,
locked submission and original receipts. Its comment explicitly leaves
persistence-before-dispatch to the host. CardModels/ActionCards offer typed local
actions and preview/save UI, not a durable Rust form/feedback store. Bot drafts
are a different object/domain and are not copied or replaced here.

This implementation persists only bounded local component values and opinions.
It does not edit Supplier/Project/Paper, send a message, approve an external
operation, create a Bot, invoke a tool, render HTML, read source bytes, or enable
an engine. UI reducers should project these durable results; they must not create
a competing persistent truth. Nothing here claims complete U06/U09 product/UI
acceptance or a native integration that was not implemented.

## Owned production changes

- artifacts/local_interactions.rs and local_interactions/tests.rs are new.
- artifacts/mod.rs exposes the actual local submodule (lib.rs stays owner-owned).
- project_access.rs adds four independently issued purposes: LocalDraft,
  LocalSubmit, LocalFeedback, ReadOwnLocal. Old Save/Discover/LookupOwnSaves
  permissions do not imply any new purpose. Issuing accepts at most7 distinct
  code-enumerated purposes, still within the existing256-byte SQL read guard.
- save_journal.rs shares bounded journal row reads, durable pending insertion,
  conditional final receipt update and phase-aware Unknown/rejection dispatch
  across two internal constant domains, Artifact and Local. Public payloads
  cannot select SQL/domain/tool names. Existing Artifact-domain SQL is unchanged,
  independently compared against de3. Original post-receipt output/source/history/
  project tail checks remain in place; no original unknown/receipt is migrated.

All storage uses the existing BusinessStore connection, owner lock and
BEGIN IMMEDIATE queue. Explicit new namespace initialization creates six tables:
artifact_local_meta_v1, artifact_local_bindings_v1, artifact_local_forms_v1,
artifact_local_feedback_v1, artifact_local_reviews_v1, artifact_local_intents_v1.
No existing schema/data is replaced or silently migrated. Partial/unknown local
schemas fail closed. These are component state/leases/reviews/intents, not
canonical messages, evidence, document bodies, grants or a second database.

## Trusted binding and permission boundary

LocalAccess is not deserializable. It holds the real host-resolved project/actor
access, exact LocalObjectRef and binding generation. LocalObjectRef contains
object ID, original Message(conversation ID + message ID + revision) OR
Evidence(evidence ID + revision), component ID/revision and attempt ID.

The host MUST resolve the actual canonical original target and current actor/
source/project policy before issue_local_binding_trusted. Never fabricate a
revision, assume existence from a model's ID, substitute latest, or treat the
component revision as the source revision. If the real source has no trustworthy
revision/resolver yet, keep that adapter unavailable. The source target revision
must be >0; component revision0 is valid under actual CardModels/ComponentLedger
contracts, which explicitly accept >=0. Synthetic tests cover this distinction.

Binding issuance persists only exact IDs/revisions, kind, fixed field policy,
short <=30s expiry, binding generation and parent project grant ID/generation/
epoch. Reissue can refresh the identical ref/spec only with the next generation;
changed target, attempt or policy needs a new explicitly selected local object.
It never resets existing values or human-edit flags. Host must revoke promptly
on canonical target/policy change, refresh only after fresh resolution, and not
rely on the TTL as its source-validity policy. The resolver/actual source-change
adapter is an owner integration requirement, not supplied by this backend.

Every current-value read/write checks live parent project authority and exact
persisted target binding. ReadOwnLocal is separate from mutation. Trusted revoke
uses the original kind's mutation purpose and exact binding; it does not demand
an additional read grant just to withdraw an existing lease. Discovery/document
permissions cannot create or use local interaction rights.

## Form and feedback behavior

Only code-enumerated Text, Choice and Selections fields exist. Host options are
<=16 distinct opaque IDs per selector. Text is <=4096 UTF-8 bytes, NUL rejected;
selected IDs must be explicitly allowed. Unknown fields/actions fail decoding or
validation. Field strings are inert values; no command/schema/method evaluation.

Human changes carry the authenticated actor ID matching the project actor and
set sticky per-field manual flags. Per-field origins retain authenticated actor
or agent/run provenance independently of the last edit; human selection does not
relabel suggested text as human content. Confirmation preserves these origins.
Text suggestions retain authenticated Ai
agent/run provenance and may only edit untouched text. AI cannot select Choice
or Selections; suggested options never become user choices automatically. No
recommendation overwrites a manual field, even with a current CAS.

prepare_local_form_submit_trusted persists a frozen preview of the exact local
values and expected revision. Its digest also binds original intent, scope,
actor, object/attempt, field policy, binding generation, project revision and
parent AuthorityBinding. Edits or lease/project/grant generation/epoch changes
invalidate old confirmation. The actual field policy is checked again in the
effect transaction. Explicit confirmation changes only this local component
record and locks it. Redo uses a new explicit object/attempt; no implicit reset.
Approval of this local save is not business or external-disclosure approval.

Feedback is only Helpful, NotHelpful or None (withdraw). It is actor-owned and
CAS-bound to the exact original target/component/attempt. It never changes source
support status, truth/verification, authorization, cost or business state.

All mutation kinds commit pending before their local effects. A pending intent
locks that object against replacement intents. Same original request returns the
original pending/terminal projection; changed parameters conflict. Unknown or
storage failure keeps pending, directs QueryOriginal and never auto-replays.
A definite semantic error is Rejected only after a one-row durable rejection.

Local values + final receipt commit together. After the last receipt write the
backend rechecks exact target lease/kind/field policy and current project purpose;
late revocation, expiry, generation or policy change rolls the effect/receipt back
and retains original pending Unknown. Binding issuance and preview writes also
check exact returned policy after their last write.

Receipt lookup is actor/project-filtered SQL and returns original operation IDs,
digest, target reference/revision and result category only. It contains no draft
text or source data. Other actors' intents equal absent intents. A receipt is a
historical save fact, not current content or a source-read permission. Original
preview lookup is separately read-only and needs a current exact target lease;
it may return an old preview for inspection but never renews its approval.

## Host/generated bridge API

All are inherent BusinessStore methods, Result<T,ContractError>:

```text
initialize_local_interactions_trusted() -> ()
issue_local_binding_trusted(&LocalAccess, &LocalKind, expiry_ms) -> ()
revoke_local_binding_trusted(&LocalAccess) -> ()
mutate_local_trusted(intent, &LocalAccess, &LocalMutation) -> LocalOutcome
read_local_form(&LocalAccess) -> FormState
read_local_feedback(&LocalAccess) -> FeedbackState
prepare_local_form_submit_trusted(intent, &LocalAccess, expected) -> LocalPreview
lookup_local_form_preview(intent, &LocalAccess) -> LocalPreview
confirm_local_form_submit_trusted(intent, &LocalAccess, reviewed_digest) -> LocalOutcome
lookup_local_intent(intent, &ArtifactProjectAccess) -> LocalOutcome
```

Native owner mapping:
- EditField/SaveDraft or explicit choice -> typed FieldChange + host-derived
  Human actor (or authenticated suggestion run), fresh expected state revision,
  retained original intent. Do not forward a UI/model-provided author as authority.
- PreviewDraftSubmission -> prepare, display exact frozen LocalPreview values;
  explicit user local-confirm event -> confirm with that same intent/digest.
- Reaction/withdraw -> React(expected revision, Helpful/NotHelpful/None).
- Unknown -> lookup original intent; preview-write Unknown -> lookup original
  preview, never automatic prepare/confirm/submit replacement.

LocalMutation, field/value enums, LocalPreview, FormState, FeedbackState and
LocalReceipt have serde contracts; LocalOutcome serializes explicitly. Generate
bridge DTOs from these real types. Construct LocalAccess/project grants only on
the trusted host after checking mounted workspace/project/conversation/message/
component/attempt/revision. Binding/grant issue/revoke are privileged host policy
seams, not untrusted UI/model methods. Enforce raw JSON/field count/text budgets
before decoding; render values as plain native text, not executable markup.

prepare/preview lookup return ContractError::Unknown for ambiguous storage/corrupt
reads; retain original identity and query. Mutations/confirm return structured
Unknown/QueryOriginal. NotFound on a preview lookup does not authorize automatic
re-submission. Current state includes pending_intent and locked submitted_intent
so the host can display saved, submitting/unknown and locked distinctly.

No core/lib.rs/FFI/UI owner file was edited. B still owns the overall artifacts
module export/combination. Host resolution, action routing, actual source-change
revocation and generated bridge/UI wiring remain NOT_IMPLEMENTED here.

## Verification and limits

15 new synthetic BusinessStore test functions (prior17 retained; total32 source
functions) cover restart/CAS, manual stickiness, strict fields/options, no automatic
AI choice, preview invalidation, generation/epoch/scope/actor boundaries, mutation-
only revocation, source-vs-component zero revisions, missing/corrupt previews,
pending locks/no replacement, feedback receipt-tail binding/project changes,
valid field-policy substitution at issuance/receipt and frozen confirmation.

All local Rust targeted/full harness, formatting and strict Clippy remain NOT_RUN,
shell127: cargo/rustc/rustfmt absent. No Rust RED/GREEN or new compiler success is
claimed. Tests were written before relevant implementation/fixes and command
attempts retained. The parent previously reported prior artifact17 GREEN/old RED;
that is not execution evidence for this new code or for shared-helper regression.

Independent SQL execution uses actual extracted DDL/queries and temporary disk
synthetic stores. It checks schema, binding SQL identity/revoke, actor/project
lookup, CAS, pending lock/reopen, receipt-trigger rollback and preservation of
Artifact-domain SQL versus de3. These are SQL-only; they do not execute Rust
SHA/serde/permission enum/clock/failure-dispatch logic or host source policy.
See LOCAL-INDEPENDENT-REVIEW.md and evidence/local-*.log. B must run actual new15,
original17, full combination and strict Clippy/format checks before acceptance.

No dependency installation, model/search/external messages, real business data,
user files, engine, deployment, main/develop, credentials, original unknown or
reservation was touched. B's combination source was not overwritten.
