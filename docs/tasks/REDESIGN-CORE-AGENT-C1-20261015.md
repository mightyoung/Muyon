# C1 — isolated Rust core Agent

Owner: rd_core_agent_writer. Scope: new core/ and this task document only.
Base: 3b4a7b27afded3f2d3007028d793aa06bd564312; parent contract b53e63c.

First checkpoint contains a std-only edition2021 crate, CLI/storage contract,
and behavioral tests for policy and physical tool execution/follow-up. Stub
intentionally denies all permissions and does no work. Expected RED failures
are semantic assertions, not compile/import errors. Local rustc/cargo absent:
compilation and Rust RED are NOT_RUN until the independent CI executes this SHA.
Root owns runner invocation and independent review. No product/old lab changes.
