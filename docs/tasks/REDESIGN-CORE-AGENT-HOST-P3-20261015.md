# Task 3 — independent host-chain checker

Initial checkpoint notes below are retained as history; scoped review fixes and
newly available local validation are recorded at the end.

Frozen inputs and expectations: commit `6795ce0`, based on approved contract
`2cd3ad0`, before new DUT implementation was read. See
`experiments/redesign/core-agent-lab/host-checks/EXPECTATIONS.md`.

Owned files are `apps/muyon/test_host/**`, `host-checks/**`, the new
`core-agent-host.yml` workflow and this report. No existing tests or product code
are changed. Positive tests use the real facade, gateway, authorization, ledger,
registered inquiry.object handler, native registry receipt and compiled Rust.
Fake HTTP implements transport only. The recorder forwards exact bytes and
waits for the child; fake child data is confined to recorder self checks.

Required workflow builds the std-only Rust binary with `cargo build --offline
--locked --release`, records source/binary SHA, then explicitly invokes
`flutter test test_host/core_agent_host_test.dart --reporter expanded` with an
absolute `MUYON_TEST_CORE_AGENT_BIN`. Missing binary is a load error. The default
full suite permits no skipped tests. Workflow dispatch `suite=positive-red` is
an explicitly labeled initial compiling-stub subset, never full GREEN evidence.

The positive test asserts successful terminal task state before inspecting IPC,
so a compiling unavailable backend yields semantic assertion RED immediately.
Expected metadata comes from the fixture's selected actual reference. The second
model response is conditional on the exact projected result; raw native record
data remains observable only in the local receipt.

Validation pending actual GitHub runner execution. Local Rust, Flutter and Dart
are absent; no local compile or product PASS is claimed. Python recorder self
checks are executable locally. Device and real-model evidence: NOT_RUN.

Raw outputs remain outside Git. Root owns fixed-SHA integration, runner evidence,
non-author review and the draft PR. No merge is authorized.

Additional negative tests use a clearly separate artificial child to exercise
malformed frame lengths/UTF-8/keys, integer typing, wrong correlation, duplicate
callbacks, untrusted stderr and fabricated receipt terminals. They are never
substitutes for the positive Rust roundtrip. Effective tool confirmation/denial,
identifier bounds and incomplete SSE responses are also covered.

Local checker verification: `python3 -B
experiments/redesign/core-agent-lab/host-checks/test_record_process.py` reports
2 tests OK, covering byte transparency/reaping and terminal no-skip enforcement.
`git diff --check` passes. This is helper evidence only, not Rust/Dart execution.

## Scoped review fixes, round 1

T3-I1: each launcher now allocates a unique `launch-*` evidence directory and
appends its child/launcher identities to `launches.jsonl`. The shared inspector
requires exactly one launch, matching manifest/directories, and every child's
recorded reap plus absent child/launcher PID. Concurrent-start checks the launch
count before cancellation and all reaps afterward. A real pair of concurrent
`/bin/cat` helper launches retains both byte streams and is rejected by the same
one-launch oracle; this is helper evidence, not a positive Rust replacement.

T3-I2: root fixed narrow reasons before DUT output was consulted:
correlation/replay=`callback_mismatch`; malformed JSON/UTF-8/keys/scalars/zero
length and incomplete header/body=`host_protocol`; 65537 length=`host_budget`;
clean EOF=`host_eof`. These tests now require that reason, excluding ordinary
timeout/budget/setup substitution. Invalid model IDs require `model_failed` and
zero `prepare`/`invoke` frames, preventing later scope refusal from passing.
The shared rejection oracle self checks reject observations representing a
missing frame bound ending in timeout, a missing identifier guard reaching
scope refusal, and a mislabeled failure occurring after prepare. These are
explicit oracle controls; compiling DUT mutation evidence is still pending.

T3-I3: contract59ddf6c corrects the historical injected readonly content-review
cases. They now use the actual host policy update API to disable read, or revoke
read while the model is pending, and assert zero invocation. No new read review
hook, effect intent, grant or approval is required. Positive and denial cases
assert no grant/approval/audit rows are fabricated. The original projection and
native receipt assertions are unchanged.

Existing local SDK was subsequently discovered under `/workspace/flutter-sdk`.
A temporary clone with the original compiling Dart stub and cached package
config was analyzed through the real analysis server with its state/cache in
`/tmp` (HOME unchanged). Commit3aad90b fixed one info-level redundant interpolation;
the subsequent complete checker analysis had zero diagnostics. No local Rust
roundtrip or GREEN is claimed. Actual runner RED/GREEN remains root-owned.

Additional root/source privacy correction: the real gateway `mask` method reads
the SecretStore separately from transport credential retrieval. The historical
positive assertion `reads == 2` incorrectly treated those reads as model sends;
it now requires a real fake-store read while retaining exactly two HTTP requests
and ledger rows as the loop evidence. Independent provider-echo cases require
the existing gateway `<redacted>` answer behavior, reject changed tool identity
before prepare, and reject or clean frozen profile metadata. Raw echoed values
must be absent from IPC, outgoing context, task/ledger errors and final answers.
The positive metadata projection, original native receipt and call pairing
expectations remain frozen. This correction follows existing gateway source and
the privacy contract, rather than adapter output.

Round1 validation: Python helper self checks pass **4/4**, including the shared
one-launch/reap and narrow rejection oracles. Strict local
`dart analyze --fatal-infos apps/muyon/test_host` on the isolated original-stub
clone reports **No issues found!**, using the existing SDK/cache and
`DASH__SUPPRESS_ANALYTICS=true` plus a `/tmp` analyzer state override. No install,
download, HOME override or positive fake binary run was used. Raw logs are
outside Git under `/tmp/rd-core-agent-host-evidence-20261015/local-checker/`.
This is static checker/helper validation; full real-Rust GREEN and compiling
DUT semantic inverse controls remain pending root's exact integration CI.

First live combination5e9b81a / CI38687677301: root reported45 passed/5 failed.
One checker defect was verified against fixed existing source: AgentTaskFactory
filters category-disabled tools with `tools.permitsCategory`; `_Session.run`
requires inquiry.object among those frozen candidates before process/model
launch. The disabled-read test's historical one-HTTP expectation was therefore
overly strict. It now requires the actual early tool_denied gate, exclusion from
candidateIds, zero HTTP/ledger/receipt/launch and no fabricated authority. The
separate revocation barrier still starts an actual model request before policy
withdrawal and requires zero prepare/invoke/receipt. This correction is grounded
in the two existing source gates, not a relaxation to match DUT output. The
original failing CI log remains outside Git.
