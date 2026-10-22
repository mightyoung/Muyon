# Group grant/receipt tail correction — actual combination validation

Parent-offered candidate68f0fb697699d3a8589fc2cc4f274edaf2b2a67d replaces
ecef00d8b296930bd40ad8f1ed06890fd7b8a7fc via integration9b1c6a774bbe9258216a61a2c82ce3c0e8bddc74.
Owned delta only: group_runtime/store.rs, tests/group_runtime_store.rs and its
new task docs. No UI/FFI/AgentOwner/BusinessStore source edits or extra exports.

Actual locked/offline cargo test -p muyon-core --test group_runtime_store:
65 PASS/0FAIL/0ignored, exit0. This is47 dedicated tests (30 new+17 original)
and18 repeated source-module tests, not65 new independent cases. Same-crate
source harness uses actual BusinessStore/store paths; it does not invoke a
Service/FFI consumer or prove canonical external node payload admission.

The fresh result includes receipt/events/consumption expiry and scope matrices,
exact terminal-row receipt checks, uncertain original-owner read handling and
actual deferred-FK COMMIT failure cases. Old RED histories are retained in owner
task evidence; this integrator did not rerun those older production snapshots.

Actual strict Clippy workspace/all-target -D warnings still FAIL101 with only
existing gateway.rs:91:12 and :357:27 emitted; no provider/artifact/group diagnostic
in this run. Complete strict gate awaits gateway owner fixed source and a0 exit.

Parent subsequently confirmed targeted source review plus retained real RED42pass/16fail, independent65GREEN and original core253 logs. Both local mutation Important findings are closed in this fixed source. Deferred-FK tests exercise actual COMMIT failure and rollback, not pre-commit simulated throws. Independent combination reviewer also verified exact owned-source matching, shared transaction/expiry/receipt boundary and no added dispatcher. Canonical context/RunLedger projection and sole original
gateway admission/host UI/FFI remain outside this patch and continue HOLD. No
external Agent execution, unknown/reservation mutation, real requests or fee action.

Earlier core391 and workspace405 belong to earlier fixed combinations and are not
retagged as runs of9b1c6a77. Public export/whole workspace compile checked separately;
actual commands and raw logs retained under evidence/. Workspace/all-target --no-run PASS at9b1c6a77; complete workspace behavior rerun completed PASS435 executions/0FAIL/0ignored,26 groups (FFI14/core421). No new counts are added to prior405 or targeted65. See workspace-group-tail-summary.json and raw workspace-group-tail.log.
