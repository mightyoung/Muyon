# Independent review: U06 / U09 bounded local interactions

Separate reviewer: `artifact_review`, read-only on production/test sources.
Fixed base: `de3ec5b56de80f30c5a98c0b22bae64ece6167ae`.
Branch: `task/artifacts-local-interactions-20261022`.
Reviewed new local_interactions.rs and dedicated tests, shared save_journal helpers,
project-purpose extension and artifacts module export. Only this review and its
independent SQL script/evidence were written by the reviewer; no git commit.

## Findings addressed during review

1. **P2: a prepared confirmation survived authority renewal.** Initial frozen
   request bound values, object and state revision but omitted binding/project
   authorization identity. Reissuing the same object under a new lease/grant
   generation could therefore confirm an old preview. Confirm now freezes and
   compares ReviewAuthority (binding generation, project revision and complete
   AuthorityBinding). The Confirm command also freezes the exact FormSpec and
   compares it with current policy before applying the effect. A direct changed-
   allowlist confirmation test also asserts Rejected/BindingMismatch with draft
   values preserved and no submitted state. Request digest
   includes both. New test source rotates binding
   and parent grant generations and asserts old confirmation fails without submit.
   Historic committed outcomes remain recoverable through original-intent lookup.
2. **P2: mutation-only issuers could not revoke their binding.** Issuance accepted
   LocalDraft/LocalFeedback alone while revocation first required ReadOwnLocal.
   The corrected trusted revoke resolves kind internally, validates the matching
   mutation purpose and exact live binding, and requires exactly one changed row.
   No extra read permission is issued. Tests cover both mutation-only purposes.
3. **Read robustness:** form/feedback revision columns now have SQL-side length
   guards, matching bounded payload reads and avoiding oversized revision text
   crossing the SQLite C ABI before validation.

The author's additional last-write correction was also reviewed: the kind/spec
returned by the final post-receipt binding check must equal the effect's original
kind/spec. Issuance and prepare also compare exact requested kind/spec after
their final writes. A valid policy replacement therefore rolls back instead of
accepting a now-disallowed selection or misreporting the requested binding as
issued. Test source uses valid replacement policy JSON, not a
malformed JSON shortcut.

An initial reviewer suggestion to reject component revision zero was withdrawn
following actual dependency inspection. CardModels.kt explicitly permits
componentRevision >= 0, and ComponentLedger uses that initial version convention.
Zero component revision is therefore valid here; the original message/evidence
source revision remains strictly positive. A dedicated test records this distinction.

## Static assessment

- All six new tables use the existing BusinessStore connection and owner
  transaction. The namespace is explicit/versioned and rejects partial schemas.
  Local component values do not replace canonical message/evidence/document data.
- LocalDraft, LocalSubmit, LocalFeedback and ReadOwnLocal are independent project
  purposes. Existing Save/Discover do not imply any. Persisted project scope,
  actor, revision, grant generation/epoch/expiry/revocation remain checked.
- Local leases bind exact original target, component, component revision, attempt,
  actor/project, binding generation and parent grant identity. Renewal cannot
  silently change target or field policy; a new object/attempt is required.
- Fields are limited to text, choice and selections with bounded host option IDs.
  Unknown field/action variants and extra JSON fields are rejected. Generated
  text has separate author provenance and cannot overwrite human-marked fields.
  AI choice/selection mutations are Unsupported; suggestions do not select for
  the user. FieldOrigin preserves separate per-field actor/agent/run provenance;
  global modified_by identifies only the last edit. Changing Choice cannot relabel
  untouched AI Text as human content. Reads check bounded unique origins, actor,
  manual-mask consistency and AI-only-Text; confirmation does not relabel origins. Helpful/NotHelpful/None feedback has no approval/tool meaning.
- Draft and feedback mutations share the real durable pending/receipt/uncertainty
  helpers. Pending locks the scoped local object; repeated original intent reads
  its projection, and a replacement intent cannot bypass that lock.
- Effects use state CAS, and the final receipt write precedes exact binding,
  kind/spec and project-purpose tail validation. Failure rolls back the effect
  before shared failure handling; ReceiptTail/Unknown preserve pending and return
  Unknown + QueryOriginal without replay or a fake durable Rejected terminal.
- Prepare stores original values/revision/authority digest. Editing or authority
  change invalidates confirmation. A committed local submission locks that object;
  redo needs a new explicit object/attempt. No external or business execution is
  provided by confirm.
- Prepare storage uncertainty returns Unknown; lookup_local_form_preview reads
  only the original stored preview. Confirm's uncertain read also returns an
  Unknown outcome. Neither route creates a replacement intent or rebuilds a
  preview automatically. Feedback exposes computed pending_intent alongside the
  last confirmed value.
- Current values/preview reads require the current exact local lease and read
  purpose. Original receipt lookup is actor/project filtered in SQL and returns
  operation metadata rather than private values. Other-actor and absent intent
  lookup are indistinguishable. Read/lookup methods do not schedule effects.

The final dedicated test source contains 15 test functions, including direct
allowlist-change invalidation between prepare and confirm and valid kind
replacement on issuance. All were read; none were executed here. The incremental
SHA-256 updates preserve the original domain-prefix-plus-JSON byte sequence.

No remaining confirmed static defect or obvious compile defect was found in the
reviewed source. This is not proof of compilation or runtime behavior.

## Shared artifact behavior

The Artifact domain SQL set (SELECT, pending INSERT, receipt UPDATE, rejection
UPDATE) was independently compared with fixed base de3ec5b5 and is exactly equal.
JournalDomain is a code enum selecting fixed SQL strings, not payload-controlled
SQL. Artifact receipt/publication/source/project tail checks remain in place;
uncertainty classification and original-intent behavior are unchanged. The shared
receipt helper also enforces the existing bounded receipt contract.

This does not replace running the original artifact regression suite against the
new shared helper implementation. Prior fixed-commit green evidence is not a
current U06/U09 passing result.

## Independent SQL evidence and execution limits

Command:
`python3 docs/tasks/artifacts-mig17-u12-20261022/independent_local_sql_check.py`

Evidence: `evidence/local-independent-sql.log`.

The script extracts actual source SQL and runs it in a temporary on-disk synthetic
SQLite store. Passed: six-table DDL round-trip; scope/actor/object/binding and grant
generation/epoch/revocation query filtering; object pending and own-lookup SQL;
real receipt-trigger invalidation with local effect/receipt rollback and pending
retention; valid kind replacement detectability; form CAS and frozen review actor
filtering; Artifact/Local domain isolation; persistence after reopen; exact old
Artifact-domain SQL preservation.

The script deliberately chooses rollback after a failed SQL guard. It does not
execute Rust Transaction Drop, serde validation, SHA-256, manual-field masks,
wall-clock expiry, confirmation authority comparison, operation dispatch or
no-retry control flow. Those remain static review only or NOT_RUN. Test source,
including synthetic trigger and restart assertions, is not passing Rust evidence.

Rust compilation, formatting, Clippy, targeted and full tests: **NOT_RUN in this
environment**, cargo/rustc absent, exit 127 retained by the author. No RED-to-GREEN
claim is supported here.

## Integration boundary / acceptance HOLD

The actual canonical message/evidence resolver, current source-policy resolver
and host/FFI/UI bridge are not implemented in this module. A short persisted lease
is not proof of source resolution. The host must authenticate identity, resolve
the real current original object/policy, issue or revoke exact bindings, and wire
save/prepare/confirm/lookup plus correct Unknown feedback before product acceptance.
No generic model payload may call trusted issuance. Existing Kotlin reducer/UI
is context, not proof of this Rust durable backend being connected.

This is reviewable local persistence code with independent SQL evidence, not a
completed ordinary-form/feedback product flow. No real model/search request,
external tool, user document, deployment or prior unknown reservation was touched.

Final reviewed source fingerprints are recorded below. Final follow-up reviewed all original six artifacts source/test files
plus the two new local interaction files. Only the intended module export,
project-purpose extension and shared journal helper extraction affect existing
code; catalog and original artifact test sources remain unchanged.


Reviewed SHA-256:

- catalog.rs: `6cf4969a1582e5daddf63bc0976d6c615003e9d2257be15ba6da164c12d708a0`
- local_interactions.rs: `fac7c8c9197087128449ae31964ba11661c8b5c6e173bf2c6727c5bbc2237548`
- mod.rs: `152a1ec4ed0f965e1fb4b4a46e36b2b1dc4d85ea53a811cb4c9169d319592480`
- project_access.rs: `1315229f4065581ef8dc6e90f022a879469ee0853caa83bc443b92cff1157fd3`
- save_journal.rs: `2d635f415aaee183a341385892972f6f2426026947a018a6adaf761ecb07c229`
- tests.rs: `cfd2190c15dc7105a0db5c5613ab1f161af1ebcd5c0e0eba018629c5822d372f`
- workflow_tests.rs: `7d6fe48dc203e653cad5f12ef56a0a8d891be263e7a808fcf30f88fedd300746`
- local_interactions/tests.rs: `7dc27ecdf8bfd2d226e9621eda920345b69755fff2194c7e5a062fdc30d51f50`


Final provenance-only follow-up: inspected FieldOrigin, bounded field_origins
validation, affected-field-only origin replacement and sorted write order. The
new test performs AI Text, then a human Choice, then confirmation; Text retains
its AI agent/run and human mask remains only on the human-changed field. No
remaining confirmed defect was found in this small addition. Reversing only the
provenance addition reproduced the previous production SHA-256 exactly; removing
only the final new test reproduced the previous test SHA-256 exactly. Other
reviewed source is unchanged. Independent SQL checks passed again. There are 15
new local test functions plus 17 existing artifact regression functions (32 test
functions in source); this count is not a current executed/passed test result.
Rust execution remains NOT_RUN here.
