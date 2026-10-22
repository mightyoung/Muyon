# Ordinary chat device evidence follow-up

The user explicitly authorized one independent observability improvement after the
09d151a9 handoff: record SDK, AVD, boot, installation, instrumentation and result
validation phases with source SHA and exit codes; independently review and commit
to PR95's original branch, then allow one new synthetic acceptance run and follow
it to a terminal state. This permission concerns the new run's own evidence only.
It does not permit reading or recovering old job 117726786359 logs/artifacts.

The existing device commands and exact two selected test classes are retained in
`ordinary_chat_device.sh`. `device-phases.tsv` records source SHA, phase,
START/PASS/FAIL and exit code (`-` while starting). A failed preparation phase
leaves `NOT_RUN` for instrumentation. Once the instrumentation command is invoked,
the outcome is `NOT_VERIFIED` until the existing runner-output checks all pass.
Command invocation is not proof that Android actually started either test.
Individual results require this new run's own instrumentation output.
Abrupt runner loss/forced termination can leave START as the last record; absence
of a terminal record must never be interpreted as PASS. Existing always-upload
behavior is retained; no fallback download route is introduced.

The standalone Python probe executes only this shell runner with disposable fake
SDK/adb commands and no sockets. It injects failures in all six phases and checks
the successful path, exact-source identity, retained exit codes and status meaning.
The pre-fix run failed in all seven scenarios because phase evidence was missing;
the post-fix run passes. Both outputs are retained in `evidence/observability/`.
This probe proves evidence behavior, not actual Android E2E success.

CI39144821029 remains FAILURE with unknown device cause and unknown individual
test outcomes. No old evidence is replaced. PR86/dependencies and I04 remain HOLD;
no legacy suite, credential/configuration read, real model call, fee, merge,
deployment, branch deletion or force push is authorized by this follow-up.
