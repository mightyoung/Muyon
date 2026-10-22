# Gateway production lint cleared; test-target lint remains red

Locked codea21fdbd3c70ea40048fe67e22d446de33ff79fb7 imported minimal owner
0e325011d6eb66962669aac284cdccf5fa0685e9 delta directly from accepted90b7.
Exactly two production expressions changed; no schema2/candidate/permission,
assertion or test source changes. Source matches owner byte-for-byte.
Independent read-only combination review passed for e4f497c9..a21fdbd3.

Actual full strict command:
`cargo clippy --offline --locked --manifest-path crates/Cargo.toml --workspace --all-targets -- -D warnings`
Rust1.93.1, exit101. Former provider1/artifact47/gateway production2 diagnostics
are gone; the next test target now emits five `clippy::drop_non_drop` errors:

| Relative to crates/ | Line:column |
|---|---|
|muyon-core/tests/document_edit_gateway.rs|162:5|
|muyon-core/tests/document_edit_gateway.rs|185:5|
|muyon-core/tests/document_edit_gateway.rs|309:5|
|muyon-core/tests/document_edit_gateway.rs|375:5|
|muyon-core/tests/document_edit_gateway.rs|485:5|

All five expressions are `drop(g);`. DocumentEditGateway only borrows BusinessStore
and has no Drop implementation; the following drop(s)/fresh reopen remains the
real store-lifetime behavior. Ask the original gateway owner to remove those
unnecessary non-Drop drops or use lexical scopes while preserving all restart,
CAS/Unknown/receipt/fault assertions. No lint allowance, fake Drop implementation
or new candidate should be introduced just to pass this quality gate.

Source owner base0e325011; integrator has not modified this test file. Parent
coordinates the next immutable minimal fix. No simultaneous source-file writers.
Raw output: evidence/muyon-combination-strict-clippy-final.log. Strict gate remains
red; further target diagnostics may appear only after this target clears.

Full workspace behavior on a21fdbd3 now PASS435 executions/0FAIL/0ignored (FFI14/core421),26 groups, exit0. Exact raw log and summary retained under evidence/. This is not a Clippy result and is not added to previous435. Group local two Important
closed, broader canonical gateway/host/evidence/Android gaps remain unchanged.
