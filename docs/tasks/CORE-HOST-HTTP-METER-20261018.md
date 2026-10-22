# Core host HTTP shared metering candidate

2026-10-18 UTC. Isolated candidate based on `b1a874c697a5db48d43bf19386ed3c0b8ee85206`.
Only core `agent.rs`, `tests/native_ports.rs` and this report change. No host,
plugin, UI, checks, authority, runtime task schema or memory implementation changes.

## Change

The existing `AgentControl` now borrows the existing `AgentPorts` during provider
execution. Host charge and checkpoint persist through `AgentPorts::persist`;
they no longer return `host_control_unsupported` or write a fixture journal.
Control polling also consults the existing host control port.

Host HTTP byte charges increment the existing task `counters.total` plus its
`wire_counters.sent/received` detail. Remaining budget is the existing task total
remaining, additionally bounded by a wire-config maximum when present. The same
task total already admits context and checks output; transport bytes therefore
reduce the budget available to the next admission and response. This is a
conservative synthetic accounting unit, not monetary or vendor-token accounting.
Nonhost fixture wire accounting remains unchanged.

Host provider entry now persists `provider_inflight=true` with cleared usage
before entering the provider. The existing inflight guard prevents re-entry
after interruption. Initial persistence failure prevents provider entry. Failed
charges preserve actual byte counters and return an error; terminal provider
failure does not automatically retry. No authorization/budget system or retry
path is added. Host evidence recovery remains host-owned and does not resume a
persisted runtime task through the fixture `State::load` parser.

## Evidence

Actual RED on the baseline: the new native-port tests compiled and failed on
`HOST_CHARGE_RED: host_control_unsupported` and
`HOST_METER_RED: shared total admission` (actual remaining `u64::MAX`).
Two other baseline tests passed; process exit 101.

After implementation, the full core suite ran with default test parallelism:
**112 passed, 0 failed** (unit 6, host 32, HTTP 11, kernel 21, native ports 6,
native protocol 5, wire 27, wire review 4). `git diff --check` passed.
Five added tests cover host journal routing/shared total, rejecting excess charge,
initial persistence failure and inflight barriers, charge persistence failure,
and response/next-admission budget consumption. Two inherited Rust warnings at
`host_session.rs:132` remain; there are no new warnings.

Command (Rust 1.99.0, offline locked dependencies):

```sh
env CARGO_HOME=/tmp/muyon-tools/cargo RUSTUP_HOME=/tmp/muyon-tools/rustup \
  PATH=/tmp/muyon-tools/cargo/bin:/usr/local/bin:/usr/bin:/bin \
  CARGO_TARGET_DIR=/tmp/muyon-build/http-core-owner \
  cargo test --offline --locked -j2 \
  --manifest-path experiments/redesign/core-agent-lab/core/Cargo.toml -- --nocapture
```

Raw evidence remains outside Git:

| Path | SHA256 |
|---|---|
| `/tmp/Muyon-http-evidence/core-native-ports-red-both.log` | `e901af84ec52a96dbe0f045f410262e4d12543ab4965eccd5db4093219f752bd` |
| `/tmp/Muyon-http-evidence/core-suite-green.log` | `4f1ea753cb320345542fba2c898ea3cda2fae7007d80113261cf702b2dc5e34f` |
| core `src/agent.rs` | `76551fb66b7a2aba5cd18f0101bfe786db3fc74ccb2d5e6d0714d141774e78b2` |
| core `tests/native_ports.rs` | `0ad7393805ae5ed4f691ef13a10c90eea31f6d29e6c59df371f58aeb9933caf7` |

Host loopback adapter/integrated HTTP tests belong to another owner. Independent
review, final combination, remote CI, Android and real endpoint/model execution
are **NOT_RUN by this owner**. No credentials, real model costs, push, dispatch,
merge or main change occurred. This is not included in the parent's f60 gate.
