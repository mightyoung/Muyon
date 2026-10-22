# Concrete adaptation and dependency gates

## Source inventory and sole writers

Current fixed developc130008bbc40d78e85d10058030da9da4aca38f0 includes five draft
methods and newer FFI tests; they must stay byte-identical during Reader adaptation.
It has no Reader13raw/7presentation wrappers or document_bridge.rs. Old5488 contains
those files; diff is3paths/1411insertions/2deletions, NOT a safe whole-branch merge.
B is preparing Office+Bot. This checkpoint changes NO production path, lib export,
Android, generated binding or legacy unknown/reservation. The staged adapter
module is tested source input validation only, not linked into FFI or authority.

Capture exact future B source/manifest first; rebase narrowly onto it. Compare
only necessary5488 Reader methods/module, retain B's actual Bot/config/Office code
and generated owner. Do not copy an old entire lib.rs/core tree/generated binding.
Parent coordinates one FFI writer and B performs final generation. Fixed Core
E/F/G/admission is pending; partial be902 A–D does not establish those methods.
No provisional success trait/JSON permission, duplicated root table or generic
issuer fallback is acceptable. No code may claim physical Android visibility.

## Group conservative gate — precise residual and required seam

Original worktree1c64 is clean. No Group gate module/source patch was written or
committed; prior fetch failure was investigated rather than assumed as rollback.
Fixed5f2644cfbcc580a0cc9a567c5272d58c35b47ac3 and predecessor88c1700eb90e7ca47bb6c022446dff329695c37a
are now available/read. Their reports confirm local source provenance, not Group
execution permission. Develop lacks request_origin/group_request_gate/
group_prepare_chat and canonical bindings. Core module export already includes
`group_runtime_store`; no shared Core/lib patch is required at this base.

Insertion after source is composed: a distinct request-only dispatch guard before
EACH existing agent_confirm/agent_claim/agent_allowed. Preserve original
`authorize_agent_request` and Owner confirm_trusted/claim_dispatch/dispatch_allowed
checks. Exact current State owner, SAME BusinessStore and real opened RunLedger;
absent owner/ledger/file, malformed/missing/legacy source, inconclusive or
`group_hold()` => reject (allowed=false). `group_hold=false` is classification only:
no removal of configuration, account/project, proof, budget, attempt, epoch or sole
claim. No provider/model request or second sender.

Important concrete namespace seam:5f gate.rs request_local_group_evidence returns
Ok(false) when ALL9group tables are absent. Subsequent Direct classification can
therefore be nongroup; it does not itself prove the namespace was not lost. Its
public initializer CREATES an absent namespace, so cannot be used as a validation
probe on existing workspace. RunLedger::open also CREATES when file is missing.

Minimal requested Group-owner public hook, no copied policy:
`BusinessStore::validate_group_request_namespace(&self) -> contract::Result<()>`
Read-only, no initialize/migrate/write; SAME owned connection validates full actual
Group namespace/DDL and workspace/version2 plus canonical binding namespace/version1.
Missing/partial/wrong-type/corrupt must error, including complete absence. This
is a denial prerequisite, not authority. No FFI second database or SQL reimplementation.
After that fixed hook arrives, dispatch guard uses it plus group_request_gate.
Never cache a successful namespace check across calls.

Normal NEW workspace: only after BusinessStore::initialize CREATE_NEW succeeds
in explicit initialize=true registration, initialize empty extension namespaces
and RunLedger once. Existing workspace must open only already-existing ledger. A path.exists check
followed by today's create-enabled RunLedger::open is TOCTOU-prone and insufficient.
Request RunLedger::open_existing(path,workspace,epoch) using no-create DB open plus
owner/source identity validation; keep its file identity/liveness rechecked at use
so deletion/replacement after open cannot yield empty nongroup evidence. Do not
lazy-create it from confirm/claim/read. The concrete owner-level API is pending.
If historical namespace is absent/lost, HOLD until explicit owner-approved migration,
not automatic empty reconstruction. New-workspace Direct regression must use actual
Owner provenance, real initialized namespaces/ledger and ordinary original guards.
Dropping whole/partial Group namespace or deleting ledger after open must deny
without recreating files/tables. Existing unknown/reserved attempts remain unchanged.

Group preparation: add a separate trusted typed selector route only after native
source is present, using GroupScope::current and RunScope::current from actual
host state, then BusinessStore::group_prepare_chat with gate::GroupChatPreparation.
Never generic prepare_chat/prepare_chat_restricted followed by a Group label.
Cross-owner budget/attempt/claim consumption remains unclosed: every Group execution
continues HOLD, even with valid local source and preparation. This checkpoint does
not introduce those exports or claim a completed Group gateway.

## Reader continuation — order of real integration

1. Require VERIFIED fixed Core source/API/report for root+child and genuine E/F/G/
   admission, not source existence or passing only A–D. First admission product
   semantics ARE approved: genuine current explicit selection/current project/
   source-known exact local registration. Explicit document revoke still blocks
   new grant IDs; lifecycle stop cleans owned chain, not a permanent document ban.
2. Add actual policy-host instance under original State mutex and same existing
   DocumentReaderHost/BusinessStore. Initialize its owner-session once after owner
   lock; no second root/grant database or on-every-call reconstruction. Preserve
   original5draft,13raw and existing7presentation signatures/behavior on B's input.
3. At actual synchronous trusted selection event, match current authenticated
   Host scope, call real Core selection_changed BEFORE issuing the new native
   selection token. Failure => no token. Capture real native selection epoch in
   pending selection AND ReadLease at initial open; keep current epoch after one-
   use token consumption.5488 lacked retained epoch, so this is a required addition.
   Native epoch is not a wire field proving current. Never register from late
   completion. Root begin attaches to actual live exact ticket AFTER initial open.
4. Convert immutable original scope/kind/attempt, root CAS, exact surface and frame
   correlations into the VERIFIED typed Core inputs; no caller allow/permission
   list/expiry/owner epoch/workspace/account or latest-grant lookup. Treat corrupt/
   missing/SQL/clock as explicit error/unknown, never natural TTL or not_committed.
   Staged adapter validates bounded ASCII/canonical u64 and equality only. It issues
   no token, current fact, display lease or receipt. Its8tests do not verify Core.
5. Prepare binds original frame/grant/CAS before dispatch, actual native challenge;
   fresh Activity observation is sampled by Host on owning Looper for THAT original
   challenge. Core authoritative checks window/correlation/root and issues child.
   First renewal creates root-owned child1 without changing unrelated parent;
   later child.next only. Generic issue_document_grant_trusted is forbidden here.
6. Renew then G remains serialized native operation/batch. G validates original
   root/attempt/native selection epoch and exact predecessor BEFORE a destructive
   core open. Real Core returns nonconstructible new ticket; never replay consumed
   selection token or derive latest/new ticket from receipt JSON. Native retains
   exact predecessor/new identities for cleanup. SQL receipt versus memory/PFD
   transfer are not one SQLite transaction; preserve original pending/unknown and
   perform explicit original reconciliation, never automatic retry/reissue.
7. Frame advance: incoming OLD original ticket/epoch/scope validated before native
   call; record actual frame_advanced through Core before publishing new response.
   Error after increment cannot pretend rollback. Old callback denial itself must
   not clear current newer frame; corresponding terminal/current denial/clear_all
   does. Current State/Host ordering and binding generation remain mandatory.
8. Drain real invalidations on BOTH success/error under native owner; map core IDs
   to old opaque IDs before removing. Expired predecessor may be absent as a live
   session but must retain its true root predecessor correlation in Core. During
   successful G, predecessor invalidation clears only predecessor output, not this
   continuing root/new frame. Never suppress notifications; unknown/clear_all HOLD.
9. Cleanup/revoke/stop cannot target a different current root/frame. Parent explicit
   revoke and external generation replacement terminally fence descendants; restart
   retains historical outcomes but no restored grants/tickets/surface. Historical
   receipt and stage correlation success never authorize display. Host must perform
   actual PFD/cache disposal and request-start deadline timers; no simulated FD.

## Gate matrix — current truthful status

| Slice | Current evidence | Remaining |
|---|---|---|
|8input/callback cases|Actual standalone Rust + independent run; original5pass/3fail retained, corrected8pass|Concrete Core conversion/types after verified API|
|Existing develop baseline|Separate offline cargo run, see evidence/runs.json|Does not exercise unregistered staged module or absent policy APIs|
|Group request gate|Source read only; no residual implementation|Fixed5f composition + readonly namespace hook + true Direct/negative regressions|
|Reader13raw/7presentation|5488 historical source, absent on this develop|Narrow B-base adaptation; preserve newer production paths|
|Core policy A–D|Parent reports partial validation|Verified fixed E/F/G/admission + all mutation/fault/revoke tests|
|New FFI policy/bindings|HOLD, no placeholder exports|True API conversion, generator solely B, offline integration + independent review|
|Host/Android/PFD|NOT_RUN|True source/Activity/scope join, G routing, timers/disposal, devices|

## Updated external blocker —19:12Z parent notice

Core task01a161d4-6bca-735e-9224-11a072aec009 was stopped by execution-service
safety checking (`possible cybersecurity risk`). This is NOT historical quota.
Parent reports28policy tests passed and D dependency7ea389df92c7800e758ec6ebb9bc578de0f96fd1
pushed, but final new-develop workspace and all remaining APIs were not delivered.
These are parent-reported partial facts, not this task's verified Core acceptance.

Actual Reader policy integration depending on those unfinished methods is STOPPED.
Do not implement missing Core methods here, copy its authorization tables, add
successful stubs, move environment/worker, or rewrite the task to evade that stop.
Only independent residual Group status, existing type/contract read-only checks
and already-existing source tests remain in scope. This recovery artifact contains
no attempted replacement Core operation. Await a new valid resolution condition.
This is an external dependency stop, not a rejection of this branch's Git/docs
or an unexecuted test result relabeled failure. No further Core policy call, new
full-API validation or production gate enablement was attempted after the notice.
