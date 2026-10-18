# A independent read-only final review

Scope: existing exact-product2f Linux, Android two-ABI/package and shipping JVM Service evidence. No builds, tests, device runs or source changes were performed by this reviewer.

## Verified evidence

- Source HEAD is `2fbdc13efd84cabf04623775f87e762cd0d08c11`. All five source manifests (Linux before/after, arm64, x86_64 and package), each containing 340 paths, independently match current source bytes. Tracked inputs remain unchanged. During the ordinary build, status contains only untracked Android Compose `.kotlin/` generated state; this is not a clean-checkout claim.
- Linux verdict records full GREEN: Rust unit3/integration6, JVM shipping5, missing-library negative and panic containment/recovery. Shipping features are empty; panic-probe features are isolated. Android runtime is explicitly NOT_RUN.
- Both producer manifests are GREEN, exact2f, API24, NDK `28.2.13676358`, shipping features empty. Actual copied arm64 and x86_64 Rust libraries match their manifest SHA256. Recorded ELF evidence includes API24 notes, 16KiB load alignment, RELRO/BIND_NOW and nonexecutable stack; Rust/JNA ELF/import evidence is retained.
- Package required Gradle log genuinely ends BUILD SUCCESSFUL with81 executed tasks. App and instrumentation APK files both match verdict hashes. Independently opened the app APK: exactly six native entries, comprising Rust/JNA/graphics for both ABIs; every entry hash matches verdict and integrator check, every entry is stored and its data offset is 16KiB aligned. Rust entries match producer artifacts. Zipalign app/test success records are retained.
- All five lint/AIDL evidence inventory hashes match actual retained bytes. Lint report says0 errors/6 warnings; do not claim warning-free. Generated `IAgentRuntime.java` is real AIDL output. Empty `AgentReplyParcel.java` is retained as recorded compiler output, not represented as an implemented Binder runtime test.
- Shipping JVM Service log executes four actual variants with exact2f/library identity, original receipt/dedup/epoch/visibility/reopen markers. Durable oracle identifies four original receipts; seven oracle controls pass. Its baseline process exits0 with no timeout, forced cleanup or remaining owned children.
- Independently checked63 raw log hashes across artifacts/package/service records: zero mismatches. Verification probe source extraction and exact source identities are separately retained.

## Limits and remaining work

Ordinary clean assembly is still running at this review; only its clean command has completed. No ordinary-build success is claimed here. Package success is the diagnostic/package gate and must remain distinguishable from ordinary assembly.

ART, Binder, UID/permissions, Android fsync, kill/rebind, physical device and emulator remain NOT_RUN. Packaging and JVM evidence cannot substitute. The JVM durable oracle explicitly does not observe actual first payload or exact handler count; no separate Rust observation is grafted onto this JVM run.

This A evidence is exact product2f evidence. It does not establish Android/package compatibility of B's combined `d25a4078` source and is not a product integration acceptance.

Outcome: scoped PASS for retained Linux/two-ABI/package/shipping-JVM evidence and artifact integrity. Ordinary assembly remains pending; device/runtime limits remain explicit.

## Final ordinary assembly and stopped-owner update

Ordinary assembly has now completed. Independently inspected actual clean/build sidecars and raw logs: both exit0, no timeout, no forced owned cleanup and no remaining children; both raw SHA256 values match. Clean executed2 tasks, then the unchanged `run-ci-checks.sh` ordinary path executed71 tasks and reported BUILD SUCCESSFUL. This closes the ordinary-assembly pending item above.

Exact2f checkout is now git-clean. Owner's final OUTCOME records all six runner exits0, tracked340 inputs unchanged and no active owned build workers. `FINAL-MANIFEST.json` actual SHA256 is `937321504a558d81f3ff39084fc6ff4924b8691937d4c7b57d6d9ca2fce5d912`, matching the supplied seal; root separately verified all219 listed files. This reviewer did not repeat root's complete219-file scan.

Final A outcome: scoped PASS including ordinary assembly; A owner stopped. Android/device runtime remains NOT_RUN, and fresh compiled Service inverses/private Rust Service13 were not rerun in this batch. Evidence remains exact2f only. This review is now closed; no additional A owner files were written.
