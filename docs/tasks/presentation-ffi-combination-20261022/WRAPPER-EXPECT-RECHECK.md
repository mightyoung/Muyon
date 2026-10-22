# Scoped source-wrapper reexport expectation

Independent minimal source commit62661af4d6afac947730ab76c15e12bbe498ecee.
Parent explicitly authorized reasoned expect(unused_imports) on the actual
#[path=documents/mod.rs] mod documents declaration in exactly these wrappers:
- src/bin/business_worker.rs: expected non-test CandidateState+CandidateStatus;
  test-mode CandidateStatus (CandidateState actually used by candidate tests).
- tests/group_runtime_bridge.rs: expected CandidateStatus.
- tests/group_runtime_store.rs: expected CandidateStatus.

Each retains full real library documents module to exercise candidate retention.
Public documents/mod.rs and reexports unchanged, no module/test deletion, no CLI
lint suppression or global allow. Exactly12 attribute lines across3files. Existing
dead_code allowances in harnesses unchanged. Independent fixed diff review PASS.

This is a MODULE-level, NOT symbol-level exception. A different new unused import
could satisfy it after the listed symbols become used; new compiler diagnostics
must still be reviewed against this manifest. Without any unused import in the
module it should trigger unfulfilled_lint_expectations under strict. It does not
permanently certify a fixed identifier list or waive later warnings.

Actual related tests: worker75/groupbridge110/groupstore122, total307 executions,
0fail/ignored, exit0. Many shared source tests repeat; no additive acceptance claim.
Compile/test log has no warnings or unfulfilled expectation diagnostic. Scoped
rustfmt3files PASS0. Core all-target cargo check PASS0 with no warning/unfulfilled diagnostic; raw
wrapper-core-check.log retained. This is rustc compiler evidence, not Clippy gate.

Targeted strict AND actual workspace/all-target strict both FAIL101 at corelib
Group store.rs460 group_consume_and_verify_tail and bridge.rs431 group_ui_workflow,
8/7arguments. No source-typed Group fix integrated yet. This stops Clippy before
all wrapper targets, so this expectation item and whole strict are NOT CLOSED.
After ownerfix, rerun all-target strict to require all3 expectations actually
fulfilled with no new warning; absence of warning in cargo check/test is supporting
compiler evidence only, not substitute for that full Clippy gate.

Native/product behavior, generatedbinding01e1c019 and earlier814testsource untouched
except wrapper lint attributes; original814 is not relabeled as newfullrun.
No sourcebranch/main/develop, publication, verified or Android change.
