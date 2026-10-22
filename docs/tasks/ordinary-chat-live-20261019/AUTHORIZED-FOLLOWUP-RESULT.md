# Explicitly authorized follow-up — evidence

Source: `292985599620a5cf1adb3835d2d554c9ec8ebd50`.
The user explicitly authorized two additional real attempts, at mostthree with
the original, total1 CNY including retained prior reservation. Original unknown
is not reopened, refunded or resent. New round still stops on any unknown.
At this checkpoint, additional provider attempts remain0.

## Trusted integration and independent source review

Fixed round identity `muyon-ordinary-chat-20261020-authorized-followup`, max2,
ceiling998690 micro-CNY; old exact ledger is locked/validated on every new-round
operation and retains1310. Sum<=1000000 and total attempts<=3. Root once-marker,
fixed private0700 sibling and no-recreation checks survive processes/epochs.
New first message uses CANARY-7391, not the original unknown payload.

The trusted Application chooses fixed new native session root only after budget
validation; attempted rounds require existing outer root/namespace/index. Old
native root and unknown stay untouched, and new unknown retains its own recovery
gate. Same Rust Agent, admission owner/DB, callback and generated APIs. No global
RecoveryRequired exception, public interface, generated binding or search change.

Architecture design/source CLEAR and independent Rust SOURCE APPROVE. A real
review finding about paired batch-field tampering was closed with fixed
grant/batch binding to frozen context; both mutation directions were RED before
the fix and GREEN after. Earlier incomplete approval was explicitly replaced.
Details and preserved failed tool/test invocations:
[AUTHORIZED-FOLLOWUP-DESIGN.md](AUTHORIZED-FOLLOWUP-DESIGN.md).

## Offline host/build evidence

| Check | Result |
| --- | --- |
| Budget groups, original11 retained | PASS19, independently rerun |
| Official reference renderer fixtures | PASS4 |
| HTTPS socket-free checks, original27 retained | PASS68 |
| Rust ordinary live-controller target, serial/sqlite flag | PASS9, independently rerun by two reviewers |
| Android preliminary test compilation/lint | PASS56s,57 tasks; lint0 errors/15 warnings |
| Exact-source native, both API26 ABIs/ELF/JNA/imports | LOCAL_LINK_VERIFIED; source unchanged, genuine bindings/retained APIs bytecmp |
| Exact-source legacy fixture+real APK/lint build | PASS1m1s,116 tasks/32 executed,exit0 |
| Exact-source followup fixture/test APK/lint build | PASS1m,79 tasks/54 executed,exit0 |
| Final lint liveChat / followupFixture | 0 errors/15 warnings;0 errors/6 warnings |

Native report `/private/tmp/muyon-live-local-29298559/local-build-report.json`;
inputs `/private/tmp/muyon-live-local-29298559/bridge-inputs`. Actual local Rust
1.93.1/NDK28.2, not the CI producer/Rust1.99 or API26 runtime. Gradle used offline,
no-daemon/max-workers2 and exact source/input properties. Existing global journal
warnings:2302 in first build,2311 in second; no shared cache was removed.

APK SHA256:

| APK | SHA256 |
| --- | --- |
| liveChat | `dbb00d898265ec8362755a116a9154ea3e0fe733ac2e0bafc4820f99f5c84d98` |
| liveFixture | `7855e949e837dbaf2acbca25ed01ba3630ff2e9228f5657fd63067be46b6b859` |
| liveFixture test | `0763fae1f01e5d3d12afef0a99c9e4dd2d6fb10dc3442609cc125c3dca0093d2` |
| followupFixture | `5dec9ab4ba11fad5ba56fa408ed7de8fd334356a770d35a25336ae4a84c83308` |
| followupFixture test | `309187f7995396a20f83b0673f9f321e1ab22bd17f6da57ae9a41a0906c29c2c` |

Both fixture APKs were independently inspected with aapt2: neither has INTERNET;
each has only its own dynamic receiver permission. Public dummy credentials and
synthetic provider IDs in these apps are not real provider acceptance.

## Device gates and preserved actual baseline

Same isolated API36 AVD restarted with existing userdata, no snapshot/wipe. Only
the explicitly named fixture package data may be cleared for tests. Real app
data/budget were not cleared and its old native root was not opened/repaired.

Before any real upgrade, read-only baseline confirmed old budget SHA256
`0743f051b0291623240dd4c10f8f0260f04b74ef1197a4279af13bbbfbcf3fc7`.
Old native root contains5 files. Hash of compact JSON of sorted
`[relative_path, sha256(file), size]` rows:
`1435d6e4db4a23ab812a95c97ccc3f3e1ebf26943b59170ed1ad5efa05971319`.
This permits byte-preservation verification after the new round without reading
or logging credentials. Source failed attempt remains20a, unchanged.

Legacy13-case selected device result: PASS13/13, all completion status0, no skips,
62.854s, `OK (13 tests)`, `INSTRUMENTATION_CODE: -1`, native adb exit0. Four exact
classes are PipeTest, LivePolicyTest, LiveOwnerTest and LiveServiceLoopTest from
the previous diagnostic result. First followup15-case device invocation FAILED:
14 passed,1 failed,24.135s, `Tests run: 15, Failures: 1`; adb process exit0 is not
a passing test result. UI test's first Send then immediately read `.single()`
from an empty request snapshot at LiveServiceLoopTest.kt61 (callsite87), raising
NoSuchElementException. The new root/proof/permission component checks passed.
Independent read-only diagnosis confirmed no identity prefs file, zero rows in
all admission/chat tables, new ledger count0/stopped0 and no runs/candidates.
ChatReadSession publishes local identity synchronously before RPC, so this was
not a backend reject or asynchronous owner-result publication. Current fixture
IME was shown10:55:14.002, controls changed15.993/16.067, hide requested17.266,
test failed17.916. This supports an unestablished click/IME/layout precondition;
it does not prove which component intercepted the physical touch.

The test repair hides IME/clears focus and waits for actual IME invisibility
before clicking, checks exact complete draft and displayed/enabled button, clicks
once, then boundedly waits for a distinct local request identity. Failure still
fails with snapshot count/status, no click retry. All subsequent terminal/answer/
history/source/receipt/budget checks remain. Production code/gates are unchanged.
Independent architect reviewed the complete repair and BasicTextField semantics:
SOURCE APPROVE/CLEAR, no production diff, no retry or relaxed business assertions.
Followup test Kotlin compilation passed12s/exit0,31 tasks/2 executed. Exact-source
rebuild and device recheck of this repair are pending. No real credential
transfer or extra model Send is allowed until
these exact-source gates and final independent evidence review pass.

API26 runtime, CI producer and PR99 API26 Settings→Send remain unverified. No
I04/containing suite or old403 retrieval; no merge/push/deploy/branch deletion;
PR86/dependency HOLD remains. Previous failure evidence is not replaced.

## Repaired exact-source gates

Runtime/test source: `6f1fcb11e63f9ef04c51e2e8c59b4425eaec5f02` (test-only
IME/identity synchronization repair; production behavior remains29298559).
Native `/private/tmp/muyon-live-local-6f1fcb11/local-build-report.json` again
LOCAL_LINK_VERIFIED, source unchanged, both ABIs and genuine retained bindings
verified. Input root `/private/tmp/muyon-live-local-6f1fcb11/bridge-inputs`.
Two offline Gradle build sets passed41s/40s,exit0,116/79 tasks respectively;
lint liveChat0 errors/15 warnings, followupFixture0/6. Existing cache warning
counts2302/2311 were preserved without cache deletion.

| Repaired-source APK | SHA256 |
| --- | --- |
| liveChat | `f5ea54014ba063cb6b5ca11e2fca7e82525888dd7f31ecfdc6ccbc98f1595d4c` |
| liveFixture | `0256f4c5396c8ea40ca1828bc208b05c5645f4c60a456bd582f1b42491adad7e` |
| liveFixture test | `877f78fa7427871bced4842da09551c20b7a17befb15bc7cdf873141dac6f61c` |
| followupFixture | `2a0ccf1cacfbec0307637028389e0e3eb4e4d36155826512070393d936b43f56` |
| followupFixture test | `219a9f808e935f853496180c2aa4b6bb73b158cae2ca8956cfc1cac765928101` |

Additional legacy Rust ordinary_chat_controller regression PASS15/15,3.35s.
The first default-TMPDIR invocation failed all15 after the first symlink-directory
guard failure poisoned the test mutex; exact first-case diagnostic reproduced
`symlink_directory` at test43. Using canonical `TMPDIR=/private/tmp` with the
documented sqlite flag and serial target passed, no code/assertion changes.
Repaired legacy device result PASS13/13,47.974s, no skips/all case completion0,
`OK (13 tests)`, `INSTRUMENTATION_CODE: -1`, adb exit0. Repaired followup result
PASS15/15,46.32s, all case completion0/no skips, `OK (15 tests)`,
`INSTRUMENTATION_CODE: -1`, adb exit0. Same five explicitly selected classes,
with no assertion removed or retry. New fixed batch/root, exact old SHA retained,
new7391 two-turn full history/source/receipts/settlement and third budget refusal
all passed. These are socket-free fixture results; additional real traffic is0
at this checkpoint.

Independent host/APK verification CLEAR: all five APK SHA values independently
recomputed; both fixture app permissions lack INTERNET; real liveChat has it.
Both ABI bridge.so bytes in all three app APKs match exact native inputs, JNA
bytes match the verified AAR; report/source/bindings fields verified. Reviewer's
first comparison used the wrong JNA input path and failed FileNotFound, then
used the specified AAR and passed without source/app mutation. Final independent
device-fact gate is pending before real credential handover.

## Final gate and local handover

Independent final gate APPROVE/CLEAR confirmed exact source/APK/native facts,
legacy13/13 and followup15/15, no skipped cases, and preserved historical failure.
The real APK was installed with `-r`, Success, without clearing any real data.

The first local credential-helper invocation returned the fixed local refusal
while the entry was opening; its exact failure stage was not recorded. No model
request occurred. The credential Activity remained active and its FIFO existed.
A subsequent metadata-only readiness call returned
FIFO_READY true, then the reviewed helper returned PIPE_SENT/exit0. Activity
metadata confirmed successful return from CredentialActivity to MainActivity.
`adb shell -T run-as ... ls` confirmed FIFO absent/exit1. An earlier raw exec-out
`test -e` probe returned a misleading status0 (raw shell exit status is not
preserved); it was not used as cleanup evidence, and no credential contents were
inspected. This was local handover readiness repair, not a model retry.

Explicitly created local conversation2; restored conversation1 remains unknown
and was not queried or resent. Read-only Service panel showed Rust READY,
revision3. Before first new Send, both checksum-valid budget headers were read:
old count1/stoppedtrue; new count0/stoppedfalse/ceiling998690/limit2. The new
7391 draft was verified complete before a single Send. The following actual
result supersedes the preceding pre-send checkpoints.

## Actual authorized followup: unknown, stopped

At 2026-10-20 03:13:28 UTC (11:13:28 +0800), one ordinary UI Send was tapped
in conversation2 with the exact synthetic first message:
`For this synthetic test, the code is CANARY-7391. Answer with that code only.`
Executed source `6f1fcb11e63f9ef04c51e2e8c59b4425eaec5f02`, liveChat APK
SHA256 `f5ea54014ba063cb6b5ca11e2fca7e82525888dd7f31ecfdc6ccbc98f1595d4c`.

- Request: `chat_d5a99e807bf042f1ac9764dfa597d04b`.
- Actual wire SHA256: `b48d6969abc5a01116ef07b2d74046c995fc3f67bbb40a57f490197b5f1ce085`.
- Admission SHA256: `d2f1b7bf56b83ba0a428e547d8605e3ee64ccbcba18c14a3326312f947ea18c3`.
- Fixed diagnostic: version ordinary-live-failure-v1, stage HTTP_HEADERS,
  outcome unknown, http_status200. No raw errors, headers or credential captured.
- Native record: ordinary-send-live-v1/admitted, synthetic=false, history0,
  model deepseek-flash, profile ordinary-deepseek-flash-canary; answer empty,
  usage null. Failure/native/budget admission hashes agree; candidate count0.
- Followup ledger: count1, stopped1, stateunknown, full-prompt bound143,
  retained reservation1310 micro-CNY, usageNone. Second new Send NOT RUN.

The code reads a response only after authorization and its single POST write;
the numeric 200 is recorded before entering HTTP_HEADERS. This proves that this
real TLS path wrote the POST and read a 200 status line. It does not prove complete
headers/body, an accepted answer, usage or actual account charge. Several parser,
read, bounds and cancellation checks share this phase; no exact cause is proved.

Independent read-only audit confirmed old ledger SHA256
`0743f051b0291623240dd4c10f8f0260f04b74ef1197a4279af13bbbfbcf3fc7`
and old native5-file tree SHA256
`1435d6e4db4a23ab812a95c97ccc3f3e1ebf26943b59170ed1ad5efa05971319`
both unchanged. No old run was resubmitted. Cumulative actual handoffs2
(old1 + followup1), accepted answers0; total held reservation2620 micro-CNY
= CNY0.002620. Actual charges remain UNKNOWN; this is reservation evidence,
not billing evidence. Both batches remain stopped. No automatic retry, release,
new root or additional credential loading is authorized by this result.

The independent diagnosis permits only offline correction and verification;
see [HTTP-HEADER-FIX.md](HTTP-HEADER-FIX.md). Two-turn real acceptance remains
incomplete, including dependent second-turn outbound history and provider usage.
