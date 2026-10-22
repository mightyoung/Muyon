# MIG20 config/UI bridge and actual workflow projection

Base 68f0fb697699d3a8589fc2cc4f274edaf2b2a67d. Own group_runtime/store.rs + new group_runtime/bridge.rs, dedicated tests and this directory. No lib/FFI/BusinessStore/AgentOwner/RunLedger/host-owner edits. Tail authority/terminal-receipt/Unknown guarantees remain unchanged and their65 tests must continue passing.

## Facts established from actual owners

- BusinessStore owns current workspace/epoch, project, persisted group registration, local grants, group CAS revision and run/node facts. Current group extension has no list/configure/UI schema API.
- AgentOwner exposes workspace, request_conversation, bounded persisted request_chain, budget, existing observation fields; no public immutable payload digest projection and no project/group/member mapping. Current pinned document-core10d3aa83e2a93581107ad2e9f44331b5ea99d866 still has the same owner interface.
- RunLedger.execute({action:snapshot,root_id,after_seq:0}) calls private snapshot/children and returns ALL historical runs (including root), even though events are truncated. It removes epoch/session/arguments and bounds the preview. Can produce real read-only scoped workflow facts without a new owner hook; fail on preview-limit, never present partial data as complete. This corrects an overly broad prior assertion that no public complete child projection existed.
- RunScope::current derives workspace/epoch/project from the real BusinessStore. The group registration supplies the root conversation. A remote child's actual conversation is unique child-..., and the snapshot contains its remote_request_id. Match original owner identity to that child conversation, not the root conversation. Store BindOriginal's conservative root-conversation check is not weakened by this read-only bridge.
- Sole gateway atomicity across owners, canonical payload digest and private owner/session fields cannot be supplied by a display snapshot. These remain precise owner hooks, not placeholders or fake permissions.

## Implemented interfaces planned

1. Add Configure local command for explicit mode/fixed leader/member selection, using existing grant/CAS/tail machinery. No owner/admin transfer or automatic capability growth. New run captures mode/members; old legacy rows are frozen from the persisted current group before changing defaults. Existing runs retain their captured configuration, leader, epoch and grants.
2. New bridge opaque GroupUiScope::current(store, selected_project, authenticated_actor_id). Bounded strict version1 read schema has no caller workspace/project/epoch/authority fields. Native group_ui_read(scope, raw, optional actual owner, optional actual ledger+host session) returns stable snake-case JSON with decimal revision/epoch strings, execution_authority:false and explicit unavailable/unknown states.
3. Reads: mode catalog (host_only initial default, fixed/per_task explicit), paginated group configurations/member roles, group get, paginated runs, run state plus live original chain observations when owner is present, original local intent status, and live workflow facts using actual RunLedger snapshot. Unknown actual usage stays null; owner budget is explicitly workspace-level, not fabricated root accounting.
4. Configuration preparation schema Register/Configure builds an exact existing GroupCommand from the host scope/actor/authority and host conversation. Does not issue a grant or write until existing trusted authorization and execute_group_local are explicitly called. Register omission defaults only a new draft to host_only; Configure requires an explicit mode. No FFI handler or dispatch added.
5. Export/FFI schemas and concrete owner-hook requirements documented for sole owners. Integration must not read arbitrary SQL paths or accept model-supplied scopes/snapshots. No paid/provider/model/search traffic or real user files.

## Verification

TDD for persisted configure + legacy-mode freezing/CAS/rollback; strict schemas/list pagination/restart/missing owner/unknown cost; real synthetic BusinessStore + RunLedger root/children and AgentOwner prepared/Unknown chains across child conversations and wrong scope. Preserve initial RED, tail regressions, independent review, full suite evidence. Independent branch push/full remoteSHA; no main/develop changes.

## Review refinements and fixed composition

Independent review reproduced real tool_pending settled cost hidden as null and a SQL-trigger undo of legacy mode capture. Both have native RED/GREEN regressions and an unchanged independent re-run. Billing-known and original-chain-resolution are separate fields; Configure now retains the intended complete existing run row set and compares it after the exact grant consume UPDATE, leaving only reads+commit. Storage interference rolls back as PendingOriginal, never a fabricated rejection.

The pinned document-core10d actual library export is also composed in a disposable snapshot. Its direct-source harnesses need `documents` imports because pinned blobs now calls document extensions. Preserve the direct cargo-test compile101 and isolated-runner lockfile collision101; use a runner depending on the actual combined library plus direct-source harnesses with those imports and one consistent pinned dependency path. No protected original files are edited. The test-harness import patch and remaining existing business_worker import hook are reported to the combiner.
