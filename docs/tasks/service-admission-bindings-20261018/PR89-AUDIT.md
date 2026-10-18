# PR89 acceptance and CI audit

Read-only inspection at fc8ffd7e061736fdf9f4897d7c1c7914d429400a on 2026-10-18. No workflow was run, rerun or cancelled. `PR89-STATUS.json` and `PR89-CI-RUNS.json` retain GitHub terminal status observations. PR89 remains OPEN/DRAFT at exact fc8.

| Exact-head run | Terminal result | Acceptance |
| --- | --- | --- |
| generic ci39109951834 | CANCELLED | Not broad Dart acceptance; cancelled inside Analyze and test every package. Setup passed; later artifact upload success does not change cancellation. |
| scoped39109951880 | SUCCESS | Scoped Rust48 and Android adapter2 plus genuine generated binding reproduction per prior handoff. |
| Compose39109952120 | CANCELLED | Retain concurrency cancellation. |
| Compose39109955916 | SKIPPED | Branch predicate; no compile acceptance. |
| Compose39110008555 | SUCCESS | Separate exact-head manual dispatch, compile/lint/state evidence. |
| API26 loop39109953658 | SUCCESS | Exact-head two ABI builds, actual x86_64 API26 Service instrumentation; physical ARM64 runtime remains NOT_RUN. |

Earlier failed/cancelled runs remain in JSON and the immutable prior FINAL-VERIFICATION at397e25e6. The f5b058eb loop failure39109364242 is not erased by fc8 success. Initial RED, owner mapping defect, budget/type defect, inode replacement failures and generator working-directory failure are preserved there. No new outcome is inferred for those runs.

## Generic workflow recursion and I04

`.github/workflows/ci.yml` calls `scripts/ci.sh`, then four `scripts/laya/test_*.py` scripts, coverage reporting and artifacts. ci.sh runs Flutter pub-get; eight package analyses; `scripts/test_verification_gates.py`; `scripts/test_doctor.sh`; all tests in eight listed Dart suite paths; coverage Python fixtures/reporting. There is no direct Cargo/experiments target. The verification-gates test copies scripts into fresh temp trees and supplies fake Flutter/doctor/coverage dependencies, so its recursive ci.sh is mocked. Doctor uses fake tool scripts.

Dart suite source search found no task.db/I04/redesign-host invocation. Inspected subprocess sites: projection/formula mutation tests run fresh Dart drivers; LE06 independent recovery runs its named Dart child in an isolated Flutter fixture; supplier ai-job crash runs its Dart fixture; inquiry/supplier hub tests may run an existing separately built supplier_hub binary; OCR test uses explicitly environment-selected Python. None names the denied original legacy script→HTTP→original Rust task.db reopen or invokes the host Rust suite. Laya test imports target its data/contract/threshold/Kaggle helpers, not experiments Rust; Kaggle helper has a subprocess API, but these unit fixtures do not identify I04.

Therefore generic CI does **not statically include the denied I04 action** through the inspected script/test graph. This is not permission to execute the broad suites, a guarantee about arbitrary environmental overrides, or evidence that all Dart tests passed. Generic ci remains CANCELLED; no rerun is authorized here. The known unsafe unfiltered Cargo route is separate: host core's cfg(test) `http_recovery_tests` module and host_http integration target, described in the prior incident ledger. Neither is in the proposed explicit `--test service_host_bridge` command.

I04 original platform denial remains DENIED_BEFORE_EXECUTION/BLOCKED with no retry/rewrite/split/alternate executor. PR86 and dependent combinations remain HOLD.

## Unbound production owners

Kotlin ServiceHostOwnerInstallation is a trusted Application bootstrap hook, not a real installation. ServiceHostOwnerSource currently supplies scope, provider metadata and handle existence only. UniFFI CallbackProvider maps current metadata but deliberately rejects review_payload, reserve_budget and commit_admission. Generic Rust ServiceProviderBridge already gates exact payload/current binding/handle/budget and requires the owner to durably reserve/recheck/consume admission. Proposed callback seam supplies that missing callable boundary only. Actual approved source/profile/reviewer/budget/ledger/credential owner remains uninstalled; real transport/secret use/model/billing acceptance remains NOT_RUN. ConfiguredChat still ends configured_transport_unavailable.

Exported callback interface additions require regeneration and recompilation of Rust/Kotlin implementors; this slice makes no general source-compatibility promise. Existing trusted Kotlin owner-source methods default deny/null.
