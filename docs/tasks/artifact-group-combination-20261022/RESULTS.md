# Actual isolated combination results

Source 1eb944e05c4377f1394ad6991b304170e5187446. Rust1.93.1/task-local toolchain,
offline locked dependencies, existing SQLite runtime linked via /tmp. No real
network/model/engine/user DB/credentials. All test fixtures synthetic new schema.

- Artifact module target: 41 passed, 0 failed. Existing17 + local/source tests,
  not 41 new independent cases. Current actual Reader/Evidence compiled together.
- Group bridge target100 and store target112 passed, 0 failed. Repeated real
  imported source modules included; not 212 independent group scenarios.
- Full workspace/all-target regression PASS, exit0: 763 executions, 0 failed,
  0 ignored, 31 groups (FFI27/core736). Includes lib152, groupbridge100,
  groupstore112, worker65 and other targets. Repeated source tests included.
  This is the new combined run, not prior639 plus separate acceptance scenarios.
- Strict all-target Clippy FAIL101. Production function too_many_arguments(8/7):
  group_runtime/store.rs:460 group_consume_and_verify_tail;
  group_runtime/bridge.rs:431 group_ui_workflow. No exemptions added locally.
  Earlier Reader worker-import and core_bridge drop diagnostics remain not closed;
  failure at core library prevents claiming later targets lint-clean.
- Full cargo fmt --all --check FAIL1, first artifact catalog.rs14 and many existing
  owner files. Full original output retained; no full-format pass claim.
- Source-supplied new journal_pending too_many_arguments allow is explicitly
  disclosed by independent review and needs parent disposition, not hidden.

No Android SDK/Gradle in selected environment; Android/FFI consumer/UI NOT_RUN,
no installation or alternate-environment bypass. This piece changes no native FFI
or generated Kotlin. Binding still db40a794fb4b903142c3d0c20a7c3c2d157d9623,
file SHA256 bf31c4debcc94e5a9758d0ade597b239a7ef734dc6bac178c4fad2dd73bf166c.
Host source fifth-method call retained, verified=false. Publication hard refusal.

Remaining product hooks: Artifact invalidation events/core mutation hook, Message
canonical identity/source guard, FFI/UI forms; Group canonical context/gateway/
AgentOwner admission/FFI/Host. Local form submissions are durable local records,
never business tool execution. Reader raw EOF closes lease; no display/PFD feature.

Subsequent authorized mechanical follow-up: see MECHANICAL-QUALITY-RECHECK.md.
New fixed8bcc fresh763PASS, productfmtPASS, GroupstrictFAIL/fullfmtlabsFAIL retained.
