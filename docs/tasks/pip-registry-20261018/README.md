# PIP-00 / 04–07 independent registry inventory

Date: 2026-10-18. Owner: delegated PIP registry audit session. This is an
evidence/documentation slice, not a production lifecycle implementation.
Core/shared-file ownership clearance and the current unified candidate remain
pending. No core, host, migration, Android, UI or OCR source is changed.

## Fixed inputs and ownership gate

- Approved plan read successfully from Library
  `libfile_770c7e7eb1088191b821981aefe99271`,
  `Muyon-Plugin-Improvement-Plan-20261018.md`, all 231 lines. Its initial
  planning-only disclaimer is superseded for this bounded work by the user's
  subsequent execution approval conveyed in the delegation.
- Initial environment checkout: main history at
  `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`, clean branch `work`.
- Audit source: F2 `3f1be180bb009a91e659c113ba5b1916e5360332`, tree
  `30ccb7d1ceda6fe66baeee0266ce961a57fd3e2e`. New isolated task branch
  `task/pip-registry-audit-20261018` starts here. F2 is an audit baseline,
  not an assertion of the current integrated product.
- Read B05 handoff at `6f4a6f103d23821ddefced88b8ebc434b60b1ea2`.
  A7965f46 and B379b1a6d remain separate candidates; B's recorded SQLite
  native-asset CI failure is not repaired or waived by this task.
- Read next ownership at `040eb0258f251b026f1fc777792cc97580c55e4e`:
  LeaderB owns Android/min26, SQLite investigation, trusted store and integration
  records; UI/OCR have separate external owners.
- Observed store candidate `fdc9aea120925229aa592c3551efab9b3f67a825`.
  Read its CONTRACT.md, supplier declaration, reader and test inventory.
  `git diff --quiet F2 <store> -- experiments/redesign/plugin-contract-lab/core`
  returned 0: this Catalog source is identical at those two fixed commits.
  This is path comparison, not approval to modify it and not store test evidence.
- Parent/LeaderB ownership clearance requested before core writes. No response
  was available when this slice was prepared. A distinct branch is not a
  substitute for that clearance. The exact current B06 integration SHA is not
  certified by an observed branch tip.

## Original task mapping and actual differences

All paths below are relative to repository root. Existing task links identify
original responsibility, not new parallel queues. Unavailable formal IDs remain
unconfirmed rather than invented.

| PIP | Original work / current owner | Observed implementation | This slice / remaining work |
|---|---|---|---|
| 00 | [B05 handoff](https://github.com/mightyoung/Muyon/blob/6f4a6f103d23821ddefced88b8ebc434b60b1ea2/docs/tasks/leaderb-continuation-20261018/HANDOFF.md), next LeaderB integration | A observer only; B isolated governance candidate with recorded red generic CI; F2 lab | Exact audit SHA/tree recorded; unified candidate, B06 evidence and shared ownership pending |
| 04 | [Rust-only contract plan](../PLUGIN-CONTRACT-RUST-ONLY-PLAN-20261015.md), [public DATA closure](../PLUGIN-PUBLIC-DATA-CLOSURE-20261018.md); registry owner pending clearance | `Catalog::register` stages all four declaration classes in local collections; dependency closure, schema and binding validation precede final mutation; generation increments once | Reuse implementation; four new consumer tests supplement existing 22-test suite. No atomic-register production patch justified for this baseline |
| 05 | Same registry task/owner | Session epoch is used in one-shot ticket names; global generation fences old tickets. Module namespace/binding conflicts reject. No bundle revocation API, host-issued per-bundle owner lease, or disposer exists | Actual gap; design below only. Do not equate a ticket or Service client lease with bundle ownership |
| 06 | Existing NativeSession/Service controller; LeaderB host owner | NativeSession seals catalog at invocation; cancel closes transport. Service seals admission, requests cancel, joins worker outside mutex, preserves recovery/unknown, drops root before observable Closed/process-slot release | Reuse whole-Service lifecycle. Per-bundle drain/resource-close contract is absent. No shared runtime patch; blocked handler, close failure and durable failure proof require the host owner |
| 07 | Existing Dart schema/storage and current supplier store; LeaderB store owner, original migration owner unconfirmed | ModuleSchema contiguous migrations/digests; StorageManager transaction/history/structure checks; native restricted schema and typed scope checks | [Supplier version/compatibility map](VERSION-MAP.md). Preserve old inputs; hosted schema3 compatibility and production authority bridging are not certified |

PIP-01/02/03/08/09/10/11/13–15 remain with their original owners. This task does
not implement the trusted reader, migration runner, projection/Service ABI,
App API26 switch, UI, OCR, providers, REMORY or RSI.

## Short design for the remaining lifecycle gap (not implemented)

1. Keep existing `Catalog`; no second registry and no Cordis/Node dependency.
   The current final publication point already provides all-or-nothing metadata
   publication for one bundle. Multi-bundle startup orchestration is a separate
   host concern; this evidence does not prove a transaction over several calls.
2. If hot per-bundle removal is actually required by the host owner, add a narrow
   trusted Rust owner handle, bound to Catalog instance identity and a monotonic
   owner epoch. Do not let plugin JSON choose an owner identity or forge leases.
   A disposer is idempotent and can remove only its own epoch; old handles cannot
   remove a replacement bundle using the same module/binding names.
3. Retain dependencies as owned metadata before enabling removal: current code
   stores relation/view counts rather than their full rows. Removing a provider
   with foreign dependents must refuse or follow an explicitly owned reverse
   dependency shutdown order. Never strand admitted references.
4. Host lifecycle must fence admission first, cancel where supported, and retain
   ownership while any handler remains active. Settle durable final/unknown
   evidence before resource release; report drain timeout/close failure without
   claiming Disabled or reusing the owner. Catalog clearing tickets is not a
   handler-drain proof. No automatic replay, data deletion, or external rollback.
5. Stage implementation after owner/design clearance: first behavior RED for
   exact old-disposer/new-epoch, foreign dependency removal, late registration,
   double-dispose and cross-Catalog handle misuse; then minimal existing-Catalog
   change. Host-owned tests must cover stop vs concurrent admission, blocked
   handler, failure to close, and failed final persistence. Do not add a wire
   command that claims to drain a handler Catalog does not own.

Candidate write paths to reserve with LeaderB before implementation:
`experiments/redesign/plugin-contract-lab/core/src/lib.rs` and its
`tests/registration.rs`/new lifecycle test; any host integration would also touch
`experiments/redesign/rust-agent-host-lab/core/src/lib.rs` and potentially
`src/service_controller.rs`. Those shared paths were read only here. This short
design still needs the parent's/registry owner's review; it does not authorize
those writes or claim that dynamic removal is a production requirement.

## Executable evidence and limits

`probe/` is an independent test consumer of the real existing Catalog with a
local path dependency, reusing its original fixture/support. It contains no
production registry or fake implementation. Test mutations and expectations:

- Duplicate DATA/RELATION/operation binding/view, missing view dependency,
  unsupported schema keyword and absent host binding: exact rejection, unchanged
  inspect state, then identical valid namespace/binding successfully registers.
- Failed publication preserves an already prepared ticket through invoke and
  result acceptance.
- Successful publication changes generation and blocks old ticket dispatch
  with zero execution requests.
- Closed Catalog refuses late register/prepare/invoke, with zero pending work.

These are characterization/regression checks, not feature TDD: no production
behavior changed. `initial-probe.log` records a real exit101: 3 passed / 1 failed
because the new test expected `unknown_field` instead of the existing
`unexpected_or_missing_field`. Correcting that expectation did not weaken the
reject/state/retry assertions. It is not counted as missing-feature RED.

Commands, source identity, statuses and retained setup failure are in
[EVIDENCE.md](EVIDENCE.md). Initial toolchain absence was resolved using a local
Rust1.90 installation outside the repository, without changing global PATH or
adding credentials. Initial fmt failed because the minimal profile omitted
rustfmt; its component was subsequently installed. Neither setup failure is
product failure. Only the new test file is formatted, with child traversal
disabled to preserve shared original support source.

No host integration tests, real user DB, migration, I04 action, HTTP/reopen
combination, model endpoint, Android build/ART/device verification or deployment
ran. Existing Auto/FullAllow/default host policy is unchanged. The tests cannot
close PIP-05/06 or certify PIP-07 production acceptance.

## Stop / continuation handoff

Deliver the evidence/docs commit for selective review; no develop/main merge,
force push, permissions/credentials/paid service change or automatic integration.
I04 remains DENIED_BEFORE_EXECUTION/BLOCKED with all dependent merge holds intact;
no retry or alternate route was attempted. Stop this task's writers after
handoff. Next session needs the current fixed integrated source, exact owner
clearance, short design review and a fresh behavior RED before core changes.

Blocking action: modify the above shared registry/host lifecycle paths.
Reason: parent explicitly requires owner conflict exclusion first, and current
LeaderB ownership response is pending. This is a coordination gate, not an
automatic-approval denial or a failed/uncertain write; no such write was tried.
