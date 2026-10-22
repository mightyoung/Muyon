# Retained original emulator target evidence

This supplement archives existing artifacts from the same completed run. No device was launched, reinstalled, contacted or retested; no code or tested source seal changed. Tested source remains `f2f9928a0a35afeb2d5956d3bc2d69406adcc503`; original three-case results and production verified=false remain unchanged.

## Newly located original launch artifact

`/workspace/host-bot-native-tools/avd/host-bot-api26.avd/emu-launch-params.txt` was retained by the emulator in the task-owned AVD directory but omitted from the earlier88-file seal. Its original bytes are now `endpoint-evidence/emu-launch-params.txt`. It records working directory `/workspace`, the actual installed official emulator executable,18 argv entries, and:

```
-avd host-bot-api26 -no-window -no-audio -no-snapshot -no-metrics
-accel off -gpu swiftshader_indirect -no-boot-anim
-memory 2048 -cores 2 -port 5580
```

The raw artifact retains each argument on its original separate line. Existing AVD config and pointer files are archived unchanged alongside it. They specify API26 default x86_64, task-owned AVD path, software SwiftShader and the exact task-local SDK system image. No credential/key file was read.

## Cross-links to already sealed run evidence

- `device-evidence/emulator-boot-second.log`: exact task SDK `system-images/android-26/default/x86_64/`, `host-bot-api26`, process17275, `qemu.avd_name=host-bot-api26`, SwiftShader/TCG software execution and completed boot. This is the second launch, the instance actually tested.
- `device-evidence/emulator-stop.json`: recorded checked own AVD `host-bot-api26`, PID17275 and SIGTERM after terminal tests. That PID is absent now; there is no live original process to query.
- `device-evidence/adbd-readonly-probe.json`: original successful handshake at exactly127.0.0.1:5581 identifying an SDK x86_64 emulator. Archived transport hard-codes that loopback endpoint and stops on AUTH.
- `device-evidence/device-install-journal.jsonl` and independent live read-only evidence retain absent initial package, actual installed synthetic acceptance APK paths/hashes and runtime identity consistent with that run. No other device endpoint was used by the archived transport.

Original filesystem mtimes: launch-params19:56:16UTC; second boot log19:57:59UTC; install journal20:08:36UTC; stop record20:19:17UTC, all2026-10-22. These are retained file metadata, not independently authenticated timestamps. Metadata/digests for the newly archived originals are in `endpoint-evidence/retained-original-metadata.json`.

## Exact strength and remaining gap

The newly recovered actual launch artifact links this task's named software AVD to explicit console port5580; standard emulator paired-port interpretation associates its ADB endpoint with5581. The sealed boot/stop PID records and endpoint handshake provide consistent corroboration. This strengthens the previously omitted actual-start-command evidence; it is not a newly created launch used to impersonate the old run.

**No contemporaneous `ss`/socket-inode→PID5581 listener mapping or saved `/proc/17275/cmdline` bytes was retained.** The stop record says the command line was checked, but does not preserve its bytes. We cannot retrospectively supply direct kernel listener ownership proof after shutdown. The remaining limitation must not be described as a captured PID→5581 mapping or cryptographic proof against an unrelated endpoint. No unrelated processes, HOME, credentials or rejected adb operation were inspected/retried.

The previous `EVIDENCE-SHA256SUMS` remains unchanged and valid. New originals, this supplement and independent review are sealed separately in `ENDPOINT-SHA256SUMS`.
