# Remote local-file credential handover — short design

The user cannot operate the emulator and explicitly authorized reading the project
`.env` and loading its API key into the emulator. This supersedes the earlier
manual-only handover instruction. No real model request has occurred.

Retain the non-exported CredentialActivity in the existing `:agent` process and
its original Application credential installer/authority/owner. Add a bounded
app-private FIFO in noBackupFilesDir. A named pipe stores no key bytes on disk.
It lives in an app-UID-owned mode-0700 subdirectory, is mode 0600, opened
no-follow/nonblocking, checked as a FIFO, single-owner,
and removed on first data, completion, timeout or lifecycle cancellation. Accept
one 16..512-byte printable ASCII key terminated by LF; bound the entire frame,
zero temporary storage, refuse extra/malformed input, never stringify/log it.
The no-data EOF before a writer connects is not successful completion. After
the first data, wait for writer EOF and validate the whole frame; LF alone must
not trigger early installation. Compare this reader's dev/inode before cleanup.

The reader runs outside the UI thread with a finite handover deadline. Manual
entry remains available and cancels the pipe. Activity destruction closes the
reader and must prevent a late credential installation. No new owner, network
listener, exported component, Intent credential extra or synthetic fallback.

A local explicit Python helper reads only the user-designated file into memory,
never executes its content or prints values, and sends the key plus LF through
`adb exec-in run-as` standard input. No key appears in command arguments, a
temporary regular file, logs, output or chat. It validates the app-private path
as the expected FIFO, bounds time and data, and never retries automatically.
Do not directly redirect `cat > path`: a removed FIFO could become a regular
file. The remote writer must open fd 3, check that SAME fd is a FIFO and matches
the public dev/inode/UID/mode identity, then and only then consume stdin into fd 3.
The remote shell and host process each have a fixed timeout. A failed check may
create an empty regular file, but must never copy key bytes into it.
Host pipe-write success alone is not application-install success. Report the
former explicitly and verify the latter by the Activity returning to ordinary
MainActivity after the original installer succeeds; never infer success only
from ADB exit 0. A failed/cancelled installation must not silently continue Send.
Default parsing accepts one strict DEEPSEEK_API_KEY assignment. An explicit
single-key-token mode accepts exactly one independent ASCII sk-token in the
designated <=64KiB UTF-8 file (Chinese labels are allowed); zero/multiple tokens
refuse. The real supplied file was examined
only by a local derived check: one such token is present, no value was returned.

First independently review this design, implement and test with dummy keys only,
including partial/oversized/invalid frame, no-data timeout, lifecycle cancellation,
single-reader ownership, cleanup and zeroization. Rebuild exact-source APKs and
run selected no-network device cases. Only after independent approval load the
actual `.env` key and resume the existing maximum-two-request ordinary Send gate.
Never clear/uninstall/reset the liveChat app or budget. Upgrade with data retained.

Independent architect reviewed these repairs and marked the updated design CLEAR;
implementation and no-key device evidence remain separate gates.

Compatibility: [Android Os](https://developer.android.com/reference/android/system/Os)
provides mkfifo/read from API21, but public fcntlInt requires API30. The public
[O_CLOEXEC constant](https://developer.android.com/reference/android/system/OsConstants#O_CLOEXEC)
is API27. The new debug remote FIFO handover is therefore explicitly API27+,
using O_CLOEXEC atomically in Os.open and no fcntlInt call. The original manual handover, APK
minimum API26, HTTPS, owner and native API26 build are unchanged. This session's
isolated emulator is API36; no API26 runtime success is claimed.
The [pipe semantics](https://man7.org/linux/man-pages/man7/pipe.7.html) explain
initial EOF, writer closure and bounded-frame handling.

## Implementation evidence (in progress)

No real key has been transferred and real model requests remain 0.
The first host dummy unit run passed 7/7. The first Android compile attempt
failed in 12s, Gradle exit 1: `Os.unlink` is not a public SDK method (pipe lines
56/73). Repair uses public API21 `Os.remove` after FIFO/inode validation, with
no hidden API or reflection. Independent review also found that the default
noBackup parent was incorrectly required to be mode 0700; only the dedicated
child should require 0700. Both findings are retained. The next Kotlin compile
passed, but lint failed in 56s with two NewApi errors for fcntlInt requiring API30;
the earlier API21 assumption was wrong. No lint suppression or hidden API is used.
The final, simpler repair gates only the new remote debug entry at API27+ and
uses public O_CLOEXEC in Os.open, removing the fcntl calls. The independent
architect proposed this option to reduce code and make CLOEXEC atomic. Final
rerun pending.

The repaired compileLiveFixtureAndroidTestKotlin, compileLiveChatKotlin and
lintLiveChat invocation passed in 35s, Gradle exit 0 (56 tasks). Independent
source review approved the repaired credential path and independently ran all
9 dummy host unit tests successfully. Exact-source native/APK packaging and
the selected device combination are the next gate, before any actual key load.

## Exact packaged source

Source `9613e29b0904f4ec516fe6450d4f83b564a5ae7b`, clean during build. Native
report `/private/tmp/muyon-live-local-9613e29b/local-build-report.json` is
LOCAL_LINK_VERIFIED, both API26 ABIs/ELF/imports/JNA/genuine bindings/PR99 APIs and
shared input verification pass, source inputs unchanged. Actual Rust 1.93.1;
CI producer and API26 runtime remain unverified.

Exact-input Gradle assembleLiveFixture, assembleLiveFixtureAndroidTest,
assembleLiveChat and lintLiveChat: BUILD SUCCESSFUL in 58s, exit 0, 116 tasks.
Lint has 0 errors, 15 warnings. Verified bridge inputs:
`/private/tmp/muyon-live-local-9613e29b/bridge-inputs`.

APK SHA256:

- liveChat: `cfc337273cc0e81e18651cd6850a2de72c140645c7662573ccbcd52fdf084392`
- liveFixture: `d828c2e1e8aa370548591cd7c409293bd45a78bcbfa2fcfb7e18b9fab269a6cb`
- fixture androidTest: `450d92722050cb5b483d6190933f43adc341f01e7e142f17338e7866b5b53ada`

Permission inspection again confirms INTERNET only on liveChat, absent from
fixture and test APK. The isolated emulator had exited between turns and was
restarted using the same AVD/userdata, no snapshot or wipe. First fixture-clear
attempt failed because the device was offline; after boot, fixture-only clear
succeeded. No liveChat app data or budget was cleared or uninstalled.

The four explicitly selected test classes (PipeTest 6, LivePolicyTest 4,
LiveOwnerTest 1, LiveServiceLoopTest 1) are running on isolated API36. No I04,
containing suite or search test is included. Real key transfer/model requests
remain 0 until the complete runner evidence and final review are available.

The first exact-9613 device invocation did NOT run the twelve cases: runner
returned `shortMsg=Process crashed.` / `INSTRUMENTATION_CODE: 0` before the first
case status. Current-boot events show fixture PID3115 failed to complete startup,
was ANR-killed, alongside startup ANRs for GMS, media, input method and Play Store;
Launcher also crashed with a SurfaceControl NullPointerException. This is a
failed/unverified device invocation, not a passing suite or a confirmed source
defect. Current emulator used software GPU and two CPUs. Normal emulator shutdown
and restart with host GPU/four CPUs is the bounded recovery, preserving userdata
and budget; no test assertion or deadline is relaxed. No actual key or API request.

The host-GPU/four-CPU rerun successfully started the selected cases. Five FIFO
cases passed, but actualAndroidShellFdGuardAcceptsFifoAndRefusesReplacedRegularFile
failed at line 123: expected exit 0, got 72 (identity check refused before copying
stdin). This functional failure remains a handover blocker; the identity guard
must not be removed or weakened. Dummy-only diagnosis will compare actual Android
stat identities, including the shell versus child-process `/proc/.../fd/3` scope.
No real key was transferred and no model request occurred.

Complete runner result: `Time: 224.133`, `Tests run: 12, Failures: 2`.
The second failure is OrdinaryChatLiveServiceLoopTest line 64: first ordinary
Send expected completed but returned unknown. Policy 4, owner fault test and
five other FIFO cases passed. This is not supplier evidence and no real batch
was consumed. Independent read-only diagnosis is checking the actual fixture
reason; no source deadline or assertion is relaxed, no request is re-sent.

Dummy Android shell probe confirmed the FD guard cause: pathname metadata was
`65077:362200:10212:600`; shell builtin test-p saw a FIFO, external `stat` of
`/proc/self/fd/3` reported ENOENT, while `stat /proc/$$/fd/3` exactly matched the
original identity. The writer shell owns fd3; the stat child does not inherit it.
The repair must pin `/proc/$$/fd/3` and keep every identity comparison. A separate
dummy probe also found adb37 exec-in does not return stdout, so it cannot read
readiness metadata. The fixed helper will use explicit no-PTY shell protocol
with stdin/stdout/exit-status, verified with dummy success and rejection cases.

Independent diagnosis of the ordinary unknown: request
`chat_ba9cf21b500348879ea75e866ea0cc79` has empty run/epoch/receipt identity in
fixture preferences; reservations/admissions/chat_attempts are all zero, no
candidate exists. Agent Service started at 09:04:23.253, configured native loader
09:04:39.425, loaded JNA 09:04:45.078, and still verified its controller closure
09:05:12.880; UI reported 2455 skipped frames. The unbound-chat window remains
5 seconds in AgentServiceClient. The initialization window exceeded it. Logs do
not identify whether the timer or a handshake callback supplied the null reply,
so do not claim the exact callback branch. No fixture ANR or native exception was
found in this later boot. Default synthetic=true before any source receipt is
not evidence that a synthetic provider was invoked: there was no run or admission.

The minimal test repair first observes existing application.agents presentation
and read-only Service readiness/visibility, then performs the first explicit Send.
It does not warm up by sending, extend the production timeout, retry the unknown,
or change owner/Rust/source authorization. Failure assertions will include the
UI reason. The current fixture data remains preserved until diagnosis completes;
only a subsequent fresh fixture run may clear its synthetic data. Real liveChat
data/budget remain untouched.

The existing read-only DTO has no provider-source field. Do not invent one or
add a public API for this test. Provider source=false is verified by the original
assertion on the first successful ordinary Send envelope; no prewarm Send is used.
Read-only refresh has no chatRpc five-second timer. INITIALIZING without a pending
chat does not retry its handshake automatically, so a bounded test-only loop may
explicitly refresh while observation is idle until CONNECTED, READY, epoch known
and Activity visible. The public visible flag is not the private visibility ACK;
the original Send authorization still checks that ACK. No test assertion claims
it observed an unavailable private field or changes the production gate.

The corrected host helper retains all directory/UID/mode/path guards and uses
no-PTY `adb shell -T` consistently. Dummy Android probes returned success 0 with
exact dummy bytes, wrong identity 72 with no delivered bytes, and missing-path
regular replacement 71 with a zero-byte file; no stdout/stderr echo. Host dummy
unit tests now pass 10/10, independently reviewed and run. These are not real key
or provider results.

The final helper/PipeTest identity repair and bounded read-only bootstrap change
received independent SOURCE APPROVE. Kotlin test compilation plus lint passed
in 13s, exit 0 (56 tasks, 2 executed). No production timeout, owner or Rust code
was modified. Next: commit this exact repair and rerun native/APK and all twelve
selected device cases before real handover.

## Final exact-source no-key verification: PASS

Runtime source: `20a2411e970a256f1b86e8199846a9aeb27410c5`.
Native report `/private/tmp/muyon-live-local-20a2411e/local-build-report.json`:
LOCAL_LINK_VERIFIED, source inputs unchanged, both API26 ABIs/ELF/JNA/imports,
genuine bindings and PR99 retained APIs/shared verifier all pass. Actual Rust
1.93.1 and NDK28.2; CI producer and API26 runtime remain NOT RUN.

Exact inputs `/private/tmp/muyon-live-local-20a2411e/bridge-inputs`; Gradle
assembleLiveFixture/assembleLiveFixtureAndroidTest/assembleLiveChat/lintLiveChat
passed in 51s, exit 0, 116 tasks. Lint: 0 errors, 15 warnings. Existing global
Gradle journal warnings remain; no shared cache was deleted.

APK SHA256:

- liveChat: `3754dc228a67fae7fa4e3ffb60a3735487657f2a88ec7cddc113c287f61c16d5`
- liveFixture: `2152997b58c3e8ac8dde978900ae6048b64c3d216a8bf1ad8678c40886680dfd`
- fixture androidTest: `90083e1c9e0f849a9271bec7da39cc17612e9566cb3e4d8f34136613cf243496`

After completing the independent pre-admission diagnosis, only fixture data was
cleared for this fresh test run. The same isolated API36 AVD used host GPU/four
CPUs and retained production liveChat data/budget. All four explicitly selected
classes ran without skips, all twelve individual status codes 0:

```text
Time: 56.63
OK (12 tests)
INSTRUMENTATION_CODE: -1
```

This includes the actual Android shell success, wrong-inode refusal 72 and regular
file refusal 71/zero bytes; strict frame/EOF, cancel/timeout and cleanup; complete
same-owner two-turn ordinary Send with exact history/source/receipts and third
budget refusal at exactly two attempts. Source mode is explicitly a socket-free
synthetic fixture with zero provider requests. Existing failed invocations and
their diagnoses above remain part of the record.

Source review and independent host dummy tests (10/10) passed. Final architecture
review of these exact device/APK facts returned APPROVE / CLEAR. This checkpoint
had zero actual credential transfers and zero real model attempts.

## Authorized remote handover and real attempt

The reviewed helper subsequently loaded the original project's `.env` once via
stdin/private FIFO, exit 0, `PIPE_SENT; INSTALL_NOT_VERIFIED`. Activity-manager
metadata then confirmed the credential Activity successfully returned to
MainActivity. The same owner was read-only verified READY before one real Send.

The first real attempt ended unknown: ledger attempts 1, stopped true, retained
reservation 1310 micro-CNY, no usage/candidate. The second Send was not run, with
no retries or reset. Provider delivery/charge remains unknown. Full sanitized
payload, request identity, ledger and limitations: [LIVE-20261020.md](LIVE-20261020.md).
