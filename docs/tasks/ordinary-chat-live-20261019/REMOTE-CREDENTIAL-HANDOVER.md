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
