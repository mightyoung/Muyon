# Offline failure diagnostic follow-up

Source: `ca29d3a86d595be93dd25e4b33112cfa57a38b04`.
This adds observability only; it does not recover the first real failure's cause.
Real runtime at that attempt remains20a. No new real Send, credential loading or
budget reset was performed in this follow-up. The current liveChat installation
was not upgraded; new liveChat APK was built only.

## Changes and independent review

Transport now carries fixed internal phase and optional strictly parsed HTTP
status100..599, preserving fixed public error and null cause. No reason phrase,
headers/body, credential, raw exception or payload is stored in failure records.
Only the same owner with a locally acquired permit can best-effort record an
unknown after attempting durable stop. A record is bounded1024 bytes, uses an
admission SHA256, fixed schema/enum, private0600 temporary file, force/atomicmove/
directory force. Diagnostic I/O and cleanup failures are isolated. Existing
records and repeated stopped calls cannot rewrite or invent new failure evidence.
This file is not a success receipt, usage record or permission to send again.

Changed production files: `OrdinaryChatHttpsTransport.kt`,
`OrdinaryChatLiveInstallation.kt`, `DurableServiceHostOwner.kt` in the existing
agentipc directory. Changed tests: HTTPS protocol check, LiveOwnerTest,
LivePolicyTest. No public interface, Rust, callback, generated binding or search
module changes. No new dependency. Short design and independent review:
[FAILURE-DIAGNOSTIC-DESIGN.md](FAILURE-DIAGNOSTIC-DESIGN.md).

Independent architect: design CLEAR; final SOURCE APPROVE. Reviewer independently
reran68 HTTPS checks and confirmed safety/secret bounds and stopped-call behavior.

## Host/build evidence

- HTTPS socket-free checks: PASS68, original27 retained; no real credentials/network.
- Budget JVM groups: PASS11, plus reference renderer/tokenizer fixtures PASS4.
- Initial Android compile/lint: PASS42s/exit0,0 errors/15 warnings.
- Local exact-source native report:
  `/private/tmp/muyon-live-local-ca29d3a8/local-build-report.json`,
  LOCAL_LINK_VERIFIED, source inputs unchanged, generated binding bytecmp and
  PR99 retained APIs verified, both API26 ABIs/ELF/JNA/imports verified.
  Actual Rust1.93.1/NDK28.2; this is not CI or API26 runtime proof.
- Exact-source inputs `/private/tmp/muyon-live-local-ca29d3a8/bridge-inputs`.
  Gradle assembleLiveFixture/assembleLiveFixtureAndroidTest/assembleLiveChat/
  lintLiveChat, source propertyca29 and live instrumentationtrue, offline,
  no-daemon/max-workers2: PASS57s/exit0,116 tasks/32 executed.
  Final lint0 errors/15 warnings. Existing global Gradle cache journal produced
  2302 corruption warnings; no cache was deleted, build still exited0.
- Initial un-escalated Gradle attempt could not initialize native services under
  the sandbox, exit1. Normal authorized cache/native access resolved this without
  source changes or dependency downloads.

APK SHA256:

| APK | SHA256 |
| --- | --- |
| liveChat (built only) | `90c2d9a703465592bf5b98c6770e3c02cbf170a75344c79b7ec9deded2a49eee` |
| liveFixture | `1ba7df80628a553c12f643309779c5cb56c2fd286aebc26362947706b561da51` |
| liveFixture androidTest | `b28c30a623120e971f96b503f140e78b3de2b436a67d5bf5e23ec8930ccb6ab4` |

## Device verification

The emulator process from the previous turn had exited. The same isolated AVD
was started with existing userdata, no snapshots/wipe, hostGPU/four cores.
Only the no-INTERNET liveFixture and its test APK were installed; only fixture
data was cleared. `aapt2 dump permissions` confirmed fixture has only its own
dynamic-receiver permission and no INTERNET permission.

Four explicitly selected classes, not a broader suite/I04:

```text
com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatLocalCredentialPipeTest
com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatLivePolicyTest
com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatLiveOwnerTest
com.mightyoung.muyon.androidlab.OrdinaryChatLiveServiceLoopTest
```

Runner: `com.mightyoung.muyon.androidlab.liveFixture.test/androidx.test.runner.AndroidJUnitRunner`.
API36 result: all13 cases passed, no skips; each individual completion status0.
Native adb invocation exited0. Final instrumentation output:

```text
Time: 99.742
OK (13 tests)
INSTRUMENTATION_CODE: -1
```

This includes pipe6, policy5, owner1 (seven fault modes), and same-owner UI1.
New checks cover private bounded immutable records, unavailable diagnostic root
without budget release, malformed response and candidate persistence failures,
HTTP401 fixed stage/status, repeat calls without overwrite/new diagnostic or
budget changes. Existing two-turn fixture/history/source/receipt settlement and
third budget refusal remain passing, with exactly two synthetic attempts.
No fixture outcome is a real provider response.

## Preserved actual failure and remaining boundary

After emulator restart, a read-only liveChat ledger check verified checksum and
the same fixed batch: count1, stoppedtrue, unknown, bound143, retained1310
micro-CNY, no usage. This round adds no actual provider evidence. Prior failure
and original payload remain in [LIVE-20261020.md](LIVE-20261020.md).
After all13 fixture cases, the same checksum-valid state was independently read
again, with zero real candidates. Full ledger file SHA256:
`0743f051b0291623240dd4c10f8f0260f04b74ef1197a4279af13bbbfbcf3fc7`.
Diagnostic/current documents contained zero matching secret key tokens.

Final independent verification: diagnostic feature and factual record APPROVE /
architecture CLEAR. The reviewer independently checked exact source/native inputs,
both ABI imports, generated byte comparison, all three APK hashes, lint XML and
fixture permission dump. The13-case device result remains fixture evidence only.
No approval to reopen the old stopped batch or to claim real provider acceptance.

CI producer/Rust1.99, API26 device runtime and PR99 API26 Settings→Send remain
unverified. I04/containing suites and old403 retrieval were not executed. No
merge, push, deployment, branch deletion or PR86/HOLD change.
