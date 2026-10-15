# C1 — isolated Rust core Agent

Owner: rd_core_agent_writer. Scope: new core/ and this task document only.
Base: 3b4a7b27afded3f2d3007028d793aa06bd564312; parent contract b53e63c.

First checkpoint contains a std-only edition2021 crate, CLI/storage contract,
and behavioral tests for policy and physical tool execution/follow-up. Stub
intentionally denies all permissions and does no work. Expected RED failures
are semantic assertions, not compile/import errors. Local rustc/cargo absent:
compilation and Rust RED are NOT_RUN until the independent CI executes this SHA.
Root owns runner invocation and independent review. No product/old lab changes.

RED execution confirmed by root: CI run38665093404 / job116195102695, source
f68db20364caf38a48f09750d5137c88a70af552 compiled using preinstalled Rust1.99.0;
1 test passed and 3 failed semantically (Auto low, FullAllow high, actual loop).
Logs remain external under /workspace/reports/rd-core-agent-20261015/.

Implementation candidate now contains typed Provider/ModelRequest/context,
Authorizer/HostFacts, ToolPort/Binding/Receipt, strict bounded durable snapshots,
actual synthetic execution, Linux flock, cancellation signal, lookup-only
uncertainty, exact receipt reconciliation and persistent byte/step/call limits.
14 Rust integration tests authored; implementation compilation and GREEN pending
independent runner. Source diff whitespace check passed; this is not Rust evidence.

First implementation6d25066: CI38665364085 compiled and passed all13 Rust tests
and release build. Independent process suite initially had3 checker/interface
assumption failures, corrected by its separate owner (duplicate-ref rejection,
context hex roles, pre-start input limit). These are distinct from proactive
source2a919c06: completed task projection now revalidates original effect evidence;
its new14th Rust test rejects trusting cached completion after evidence damage.
Five isolated inverse mutants now include restoring that earlier cache trust.
Latest source and mutation runtime remain pending the next exact-candidate CI.
