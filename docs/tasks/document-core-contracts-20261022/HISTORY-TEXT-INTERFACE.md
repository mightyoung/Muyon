# Explicit historical metadata authority / Text / combination exports

Starting source: `a27f04aa2460971940d4bdf2c8263bdf81f381c2`.
Read artifact owner's `CORE-HOOKS.md` and report at
`4eec6d164e84d87c74b6bc92f45ecb1e3138f680`, and evidence owner's handoff at
`741274f6ef628501cc8c75c61f156b9f003c81d7`.

## Policy decision and concrete API

Current revision authority never implies historical authority. Use existing
BusinessStore/SQLite and AuthorityBinding; do not duplicate document bodies,
heads, blob or grant truth in artifacts/evidence. New explicit versioned policy
table `document_history_grants_v1` stores only narrow historical permissions.
Initialization is explicit (`initialize_document_history_trusted()`), leaving
existing six-table document schema and its data unchanged. No silent migration.

Host-only `issue_document_history_grant_trusted(current: &DocumentAccess,
historical: &DocumentRef, operations: &[DocumentOperation], expires_at_ms: u64)`
requires real current head/grant, same document/scope, existing canonical older
revision and an explicit trusted host historical-access policy decision. It
persists exact parent grant ID/generation/epoch, current and historical refs,
read operations and a <=30-second expiry. Host must derive live actor/group policy;
neither a model's request nor a bool is that decision. Parent expiry/revocation/
generation/head changes invalidate the permission. Explicit historical revoke
is also supplied; no fallback to latest or automatic permission renewal.

`pub(crate) document_history_access_in_transaction(tx: &Transaction<'_>,
current: &DocumentAccess, historical: &DocumentRef,
required: &[DocumentOperation]) -> Result<DocumentMetadata, ContractError>`:
same live transaction; required operations must be nonempty read operations.
Authenticate current access against real current head and persisted grant. If
historical equals current exactly, ordinary exact current authority suffices.
Otherwise require same scope/document, strictly older registered immutable
revision and explicit matching active historical permission. Cross-check SQL
revision key and complete canonical payload identity. Recheck both authorities
before return, within the same transaction. A page with one denied target fails
atomically. No bytes, lease, renderer, restored head or historical write authority.

Grant-only publication tail hook remains for commit only; never use it alone
to read a historical artifact/source. Receipt/byte-delivery boundaries must
recheck the corresponding historical authority too. Missing history-policy
initialization/permission denies old reads; existing current reads keep working.

## Text metadata

Add `DocumentFormat::Text` (`text` on serde wire) because Unknown cannot identify
a known plain-text source. This adds no parser/encoding default or supported
capability. Evidence owner must explicitly request Utf8Text, verify original
length/hash and actual UTF-8, reject inconsistent PDF/other format inputs, and
preserve failure/unsupported states. Do not relabel a PDF as Text to extract its
bytes, infer encoding from this enum or enable Unknown as generally readable.
Text has no fabricated PDF page or DocumentAnchor geometry. Existing format
identity encodings remain unchanged; new Text has its own source identity.

## Module exports

Provide an unapplied `combination-module-exports.patch` for artifacts, evidence
and bot_drafts. The original branch's lib.rs stays valid and unchanged; apply
only on the designated combination branch after all three real modules exist,
then compile/test the combined source. This patch alone is not integration.
The evidence and artifact owners must consume the new format/history API in
their own directories, not through this core owner's edits.

## Verification scope

Tests first: implicit history denial, explicit exact grant success, revoke/
expiry/generation/current-head/scope/target rejection, SQL identity corruption,
missing history, no historical write operation, foreign transaction and Text
serialization/default capability. Preserve local NOT_RUN if Rust unavailable;
independent review and actual authorized verifier execution remain required.
