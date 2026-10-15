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

## Required compiling DUT inverses

The three inverse anchors were selected from fixed Dartb3f012e and the Rust
common-loop source3be2b55, without changing an author branch. New independent
boundary oracles supplement the original positive test; its assertions remain
unchanged. Projection and one-driver baselines/mutants always use the real
compiled Rust binary and original registered inquiry handler. The artificial
child is confined to the negative wrong-native-call correlation oracle.

- Projection: add the genuine result reference's forbidden nativeProjectId field
  to `projectCoreInquiryResult`. The oracle reads captured host-to-core
  tool_result first and checks the exact frozen five-field reference projection
  with `HOST_PROJECTION_FIELDS`, before checking task state. Later Rust refusal
  alone cannot kill this mutant.
- Authority correlation: remove only the call_id comparison in common
  checkProposal. The negative child attempts prepare/invoke with a different
  native model call ID. The oracle checks zero actual registry receipts first
  with `HOST_AUTHORITY_BINDING`, preventing a different protocol/task error from
  counting as the expected failure.
- One driver: disable only the active-session guard. Both ordinary starts settle
  through the real binary; the oracle first checks the append manifest has one
  physical launch with `HOST_ONE_DRIVER_LAUNCH_COUNT`, then checks task status.

`host_inverses.py` runs each exact unchanged oracle on a private baseline copy
before its own private mutant copy. Package roots are remapped into each copy,
and every mutant runs real Flutter compilation via `flutter test --no-pub`.
JSON reporter evidence must show the exact named test started and ended in one
matcher failure with its boundary marker, one failed test, terminal failure and
exit1. Compilation/setup errors, exceptions, timeouts, skipped tests, extra
failures and survivors do not count as KILLED. Logs, reporter JSON, source/binary
hashes, patches and mutated source artifacts stay outside Git; original source
and binary hashes must remain unchanged. Copies are removed after execution.

The required host workflow now invokes these three DUT inverses and, separately,
the Rust owner's `core/host_mutations.py` two host-callback/admission inverses.
The existing laboratory inverse suite is unchanged. Initial positive-red
dispatch skips these full-GREEN gates explicitly. Local Python classifier/copy
self checks and strict analysis validate only the harness; actual baseline
GREEN and compiled mutant KILLED counts remain pending exact runner evidence.

Inverse harness local verification: classifier/copy self checks **3/3 PASS**;
existing recorder/rejection self checks **4/4 PASS**; each proposed anchor occurs
exactly once at fixed Dartb3f012e. Strict local analysis of all test_host files,
including the new oracle file, reports **No issues found!**. These results do not
claim any actual DUT mutant KILLED or replace the pending real-binary CI runs.

## Existing inverse infrastructure repair after research pause

CI38689639311 (source4c4a336) retained the main host suite's 50 PASS but
rejected the first inverse baseline before creating a mutant. Diagnostic-only
commit18e1ebe preserved that failure and added bounded sanitized diagnostics.
CI38690490578 (source9692108) then established the actual setup cause: Flutter
could not read the private copy's `.dart_tool/package_graph.json`; the target
never started. This is setup failure, not semantic RED or a mutation kill.

The private copier now includes that existing resolver dependency graph,
byte-identical to the source workspace, after verifying all copied tracked
pubspec/lock inputs are byte-identical. Its package config still redirects
local packages to the private source copy. Dependency input/config/graph hashes
join the source manifest and final unchanged check. No prior build/test output
or native-assets result is copied, and no local dependency download is used.

T3-INV-1: all three inverse tests unconditionally run full-launch verification
in finally, after any target assertion. The inverse-specific fixture writes
recorder evidence directly to the retained directory so watchdog interruption
cannot hide an extra launch. The runner independently requires each manifest
entry to match its launch directory/record, each actual child to have exit/reap
evidence, and every recorded child/launcher PID to be absent. It checks all
actual launches, including the one-driver mutant's extra process. A target
marker without valid cleanup evidence is INVALID, never KILLED.

T3-INV-2: the watchdog owns a private process session and verifies recorded PID
start identities. Linux subreaper adoption permits waiting/reaping orphaned
workers. Normal exit is followed by a bounded ownership scan; remaining owned
processes receive TERM then KILL if needed. The final record distinguishes
natural completion, host.close cleanup after the oracle and watchdog-forced
cleanup, with owned/adopted/remaining PIDs. Baselines require natural reap;
mutants require complete verified cleanup. Timeout remains INVALID even when
cleanup succeeds. No machine-wide process termination is used.

Local verification: inverse infrastructure Python self checks **8/8 PASS**,
including real timeout cleanup of a TERM-ignoring grandchild in a separate
session, normal exit without forced cleanup, and rejection of a missing exit
record for either of two launches. Existing recorder/rejection self checks
**4/4 PASS**. Strict `dart analyze --fatal-infos apps/muyon/test_host` reports
**No issues found!** in the existing isolated compile clone; raw logs are
retained externally. These helper checks
are not DUT mutant evidence: actual compiled baseline GREEN and precise mutant
KILLED remain pending the next exact CI candidate. Original positive expected
projection/receipt/call pairing and all three boundary markers remain unchanged.
The inquiry integration remains paused and is not a public plugin API freeze
or an authorization to merge.
