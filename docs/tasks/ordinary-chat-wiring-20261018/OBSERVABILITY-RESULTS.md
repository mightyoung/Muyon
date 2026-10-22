# Observability follow-up — terminal outcome

Reviewed implementation and tested CI source:
**d9892a75775e507d585f3ddaa712305be30dcfac**.
One new authorized acceptance:
[CI39183528428](https://github.com/mightyoung/Muyon/actions/runs/39183528428),
attempt 1, terminal **completed / failure**. No rerun or cancellation.

Rust six-test/actual binding reproduction and both API26 ABI producers succeeded.
The fixed APK/test APK/lint/package-inspection step succeeded. New package-device
job **117841491609** failed in the device step; upload succeeded.

The new run's own job log was read successfully once, without accessing any old
job log or artifact. Its device-step output, full jobs metadata and derived phase
records are archived in `evidence/observability/`. The derived TSV comes from this
new log, not from downloading the uploaded artifact.

| Phase | Command/pipeline exit code |
| --- | --- |
| SDK | 0 |
| AVD | 0 |
| boot | 0 |
| install | 0 |
| instrumentation | 0 |
| result | 1 |

Instrumentation exit 0 establishes transport completion, not test success.
AndroidJUnitRunner reports **Tests run: 2, Failures: 1**. The owner contract test
`pinnedContextGenerationAndOneShotAttemptAreEnforcedBySameOwner` finishes with
status code 0 (PASS). The Compose loop test finishes with status -2 (FAIL), at
`OrdinaryChatServiceLoopTest.kt:56`: the `send-service-read` button is Disabled
when the test asserts enabled for the second prompt after Activity recreation.
The first-send/response, separate Service PID, one attempt and recreated identity
assertions precede that line; reaching it is evidence that those earlier
assertions completed in this run. The complete Compose regression remains FAIL;
the second-send quota-denial assertion was not reached. Why the button is disabled
is not established by this bounded follow-up and no behavioral fix is supplied.

The observation change works in local fake-tool probes (seven subscenarios) and
in this new CI's phase output, retaining the failed final result. It does not
turn ordinary chat acceptance green. A later scoped diagnosis would compare the
post-recreation selected conversation/draft/send-enabled state with the test's
assumption, using this new evidence; no further run is started here.

Old CI39144821029 remains FAILURE with unknown cause and unknown individual
test outcomes. New results are not attributed to that old run. No denied old
logs/artifacts, I04/full suite, real model/credential/fee operation, merge,
deployment, force push or branch deletion occurred. PR86/dependencies remain HOLD.
Source writer stopped after d9892a75; final follow-up changes are evidence/docs.
