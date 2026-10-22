# MIG20 configuration and actual workflow UI bridge

Implemented on isolated `task/mig20-group-config-bridge-20261022`, based on fixed `68f0fb697699d3a8589fc2cc4f274edaf2b2a67d`. Changes are confined to group runtime/store, new bridge, dedicated tests and these artifacts. No protected lib/FFI/core-owner/Android/host files, dependencies or lockfiles were edited. Original saved checkout remains clean on work. No model/search/provider/tool network execution, real user files or historical Unknown/hold were touched.

## Delivered behavior

- Real local Configure operation uses the existing BusinessStore project, durable registration, exact trusted grant, revision CAS and transaction-tail receipt checks. HostOnly remains the new-registration default; fixed/per_task require explicit user selection. Existing runs retain mode/members/leader/epoch; legacy mode is frozen atomically from the prior persisted group before defaults change. Configuration affects future runs, not global revocation or account/owner transfer.
- Stable strict v1 native bridge reads actual group/member/mode/leader/configuration and run/node/summary/stop/deadline/pending/intent state. Pagination and byte limits are enforced. Native project/principal/epoch scope cannot be nominated in JSON. Prepare creates an exact command without issuing a grant or writing. Coordinator roles do not grant management or execution rights.
- Actual RunLedger snapshot supplies all lifetime child rows even after presentation events have been pruned to256. Root is excluded from child counts; actual child conversations are matched to actual AgentOwner request chains. This corrects the earlier overstatement that complete child projection was unavailable. No display snapshot is used as admission permission or complete attempt/accounting history.
- Real owner original status, known charged usage and held reservations are preserved. Unknown/unavailable actual cost is null. tool_pending/tool_consumed known billing is separate from unresolved original-chain state. Budget is explicitly workspace-owner budget, not fabricated root accounting.
- Configuration's intended complete existing run-row set is verified after grant consumption and all trigger-capable writes. Trigger damage rolls back group/run/event/receipt/grant and returns PendingOriginal. Existing fixed expiry/identity/scope/terminal-receipt guarantees and Unknown/no replay remain covered.

## Verification and independent review

All runs are offline on synthetic databases/events. Actual owner prepare/confirm/claim returns synthetic request bytes which are never transmitted; settle fixtures are synthetic responses.

| Check | Result |
|---|---|
| Full current core test suite (`verify.py`) | 291 passed,0 failed |
| Bridge target | 38 passed =20 new task tests+18 source-imported repeated tests |
| Existing store target | 65 passed =47 existing group tests+18 repeated source tests |
| Standalone runtime/governance | 20/21 passed with warnings denied |
| Format / source and document diff check | passed; raw logs retain blank EOF lines |
| Independent original counterexamples/control, unchanged assertions | 3/3 passed after repair |
| Independent final native bridge/store | 38/65 passed |
| Structural JSON schema validation |9 valid,21 invalid examples checked with preinstalled jsonschema4.26.0 |
| Combined fixed document-core10d actual exported library + bridge/store harnesses |67+94=161 executions passed after explicit documents test-module imports; repeated source/document tests included |

Counts are test executions, not all new distinct cases. Full-suite291 already includes bridge38/store65 and repeated imported modules; do not add them as separate new coverage. Combined161 is a separate integration experiment, not161 new tests. Existing core-agent-lab runtime read/write extern warnings remain; combined fixed core also has its existing dead-code warnings, preserved in logs.

Independent reviewer found twoP2 correctness defects: settled tool_pending cost hidden, and a legacy freeze write undone by a SQL trigger despite Committed. Both were reproduced in original independent sources and native RED tests, repaired, then independently rechecked without weakening assertions. See `INDEPENDENT-REVIEW.md`, original failure logs and final re-review. No remaining important finding reported.

Historical evidence is retained: missing-API compile101; initial19pass/6fail; boundary29pass/3fail (one event-count fixture mistake was corrected to use an actual Unknown remote child, not claimed as product defect); unconfigured-owner1fail; review1pass/2fail. Subsequent passes are separate files. A staged whole-payload diff check exits2 on raw test logs' blank EOF lines; the source/document-only check passes. Raw evidence is intentionally not normalized. Raw combined core test compile101 is also retained: pinned blobs now requires document extension methods, but direct-source group harnesses and existing business_worker omit documents. Isolated runner initially hit a duplicate-path package-lock collision101; consistent pinned dependency paths fixed the runner. Both failed logs remain. The final reproducible composition uses a locked standalone runner depending on the actual combined production library and imports documents in copied direct-source harnesses only.

Reproduce:

```bash
python3 docs/tasks/mig20-group-config-bridge-20261022/verify.py
python3 docs/tasks/mig20-group-config-bridge-20261022/verify-schema.py
python3 docs/tasks/mig20-group-config-bridge-20261022/verify-combination.py
```

Scripts use the verified `/tmp/mig20-rust` toolchain and existing offline Cargo cache; they install nothing. Final manifest records commands, times, exit statuses and source hashes. Combination script uses immutable document-core10d archive and only a disposable temporary tree; it does not mutate owner checkouts.

## Deliverables and owner integration

`INTERFACES.md` contains exact implemented native signatures, response meanings, schema limits/examples, current actual owner facts and precise missing hooks. `read-request.schema.json` and `prepare-configuration.schema.json` are machine-readable v1 requests. `CORE-EXPORT.patch` is the full export patch against document-core10d, while `CORE-EXPORT-INCREMENTAL.patch` adds only bridge when older group exports are already combined. Apply one by sole core/lib owner. `TEST-HARNESS-COMBINATION.patch` gives the two group direct-source test imports required when combining with document-core; do not apply before documents sources are present. Existing business_worker and other source harness imports remain their owner's integration work.

Pending owner hooks, not implemented or denied here: real authenticated host principal/project context; read-only AgentOwner persisted canonical request binding; durable trusted group-context-to-original mapping; richer private RunLedger admission/attempt/lease/root-budget projection; sole gateway atomic recheck/claim integration; FFI state/confirmation plumbing. Existing FFI state mutex + authorize_agent_request + owner.claim_dispatch/agent_allowed is the actual gateway and must remain unique. Separate SQLite connections are not a cross-database atomic transaction. UI read/local configuration is real and usable now; canonical execution certification is explicitly unavailable until those owners connect it. No empty trait, pretend external Agent success or fabricated authority is supplied.

NOT_RUN: Android/FFI integrated UI acceptance, external Agent execution, real model/search/provider calls and deployment. They were not part of this owned-file slice; real network execution remains prohibited. No action was denied; no remote operation was left with uncertain outcome. Parent coordination is required for protected owner integration, not renewed broad user authorization.

Remote push/full SHA and main/develop comparison are recorded separately in `REMOTE.md` and remote evidence.
