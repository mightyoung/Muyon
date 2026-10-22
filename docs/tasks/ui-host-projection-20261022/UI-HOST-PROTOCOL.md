# UI host continuation protocol — implementation boundary

Compatibility baseline: 98e5b6529cfbd9313c5fea73db168eebcfd4cfbc.
Existing chat_snapshot schema1 stays unchanged; the shell's strict consumer remains valid.
Only ProductChatRuntime.kt/ProductService.kt and dedicated tests are implementation-owned.

## Real facts and gaps

Existing native AgentPlan gives request_id, request conversation, configuration_id,
payload_digest and reserved amount. Observation gives native request state and
ledger cost fields; actual cost uses the previously reviewed completed+attempted
proof rule. Session/project/mounted generation are captured by the runtime and
workspace comes from the Service. None supplies message/component/attempt/action/
original business intent identity or component/state CAS. The payload digest is an
outbound payload digest, not a card/approval digest: never substitute it.

Existing native business plans and results are separate gates with plan/intent IDs;
there is no proven join to typed-card identities. Existing BotSetupDraft is a real
in-memory local reducer; creation observations are passive seams, not a backend.
AgentCatalog is local organization, not an execution/creation backend. No backend
agent create/start, durable draft save, receipt/CAS/attachment/task/source/report
producer is introduced. Capability/material offers without trusted metadata stay empty.

## New explicit reader: chat_card_candidates, schema1

Payload is identical to chat_snapshot: original request_id, displayed conversation_id,
nullable project_id and actual integer scope_generation. Same Binder/UID/session/
epoch/scope checks. No implicit lookup on mounting/configuring or unknown recovery.

Response inner status=read_only, schema_version=1, projection_type=card_candidates.
request_snapshot embeds the existing version1 read-only result. candidates is a
finite-kind list containing only request_observation with original native request_id,
its native request conversation and optional actual configuration_id. binding=null;
no CardBinding/OriginalCardRequest/ComponentSnapshot is manufactured. The only
supported candidate operation is explicit query_original (local read via the fixed
chat_snapshot endpoint and exact captured original ID). execute/cancel/save/create/
start remain disabled with reasons. This cannot enable existing typed card actions.
The shell may render it as a read-only candidate; actionable typed cards still need
trusted core identities. Native model answer/commands never reach this projection.

## Local-only setup draft: chat_setup_draft, schema1

Required scope: displayed conversation_id, nullable project_id, actual integer
scope_generation; workspace/session derive from Service. Operation is a finite local
whitelist, never model dispatch. No native port, credentials, network or catalog
write is called. The sole underlying reducer is existing BotSetupDraft.

- open: returns the same existing scoped draft; does not overwrite text on repeats.
- read: requires exact local_draft_id and returns that draft.
- edit_name/edit_purpose/edit_role: exact local_draft_id, expected_local_revision,
  and value. Existing reducer validates text.
- next/back/cancel/resume: exact local_draft_id and expected_local_revision.
- suggest_role: same local CAS, uses only LocalSetupTemplates. Returns the actual
  ephemeral suggestion request ID and local template source, never model output.
- accept_role: same local CAS and exact suggestion_request_id captured from the
  displayed draft. Edits/cancel invalidate that token; it cannot overwrite a
  manually locked role.

local_draft_id is the actual newly created ephemeral local reducer identity;
local_revision is a host memory CAS counter for accepted local operations only.
Neither is a business intent, component revision, original request attempt, saved
version or creation receipt. Repeated mutations using an old local revision reject
without applying twice or retrying against a newer snapshot. Read/open do not advance
revision. Scope change/release destroys local drafts; no persistence claim.

Response: local_only, schema_version=1, projection_type=setup_draft; actual scope;
local_draft_id/local_revision/reducer_revision; step, name/purpose/role, cancelled,
local suggestion token/source; capability_metadata_status/material_metadata_status
are unavailable with empty allowed_capabilities/allowed_materials (no trusted offers
projected, not a claim that the underlying registries/documents are empty); saved=false,
creation_status=not_requested, agent_id=null, intent_id=null, held/actual=null,
can_create=false, can_start=false, can_save=false. Finite local operation enablement
reflects reducer state. Unsupported backend operations reject before any state change.
No create/status observation method is exposed through this endpoint.

The host retains at most32 scoped drafts. Capacity affects only new draft opening;
no business request gate is changed. Invalid scope, mismatched/evicted draft, stale
revision, unsupported operation or token rejection returns unavailable with a stable
code, no latest-draft substitution or backend side effect. Shell keeps its mounted
callback guards and uses one source of draft truth; do not maintain a UI reducer and
an IPC reducer as two independently editable copies. Adopting this host API needs
shell-owned integration; existing UI-only draft editor remains available meanwhile.

## Verification planned before delivery

Test first: original request vs later request/config generations, stale/cross scope,
unknown actual0, finite disabled operations; local open/read, CAS/repeated mutations,
invalid text/token, manual role locking, cancel/resume, release/scope remount and
no port/transport calls. Independent non-author review plus actual Kotlin JVM runs.
Android build/toolchain limits remain unchanged and cannot be replaced by JVM tests.

Implementation status: protocol-first publication was473c13f13403f309b269caf258b1b7410af09b06.
The subsequent implementation commit on this branch supplies these methods; consume
that full reviewed SHA from the delivery report, not the protocol-only checkpoint.
No document/material truth store or replacement source/version/anchor is introduced;
future material offers must consume the shared authorized Rust documents producer.
