# F2 Android independent final evidence review

**C0 within Android verification scope: PASS, no remaining blocking finding.** Exact candidate `3f1be180bb009a91e659c113ba5b1916e5360332`. This conclusion is limited to the native/JVM/build/package checks below. It is not an overall merge recommendation, generic-CI verdict, or acceptance of unresolved Claude I04/I05 work.

Read-only source/artifact review; reviewer changed only its own `/workspace/batch4/evidence/android-review/` files. No source changes, Rust/Gradle builds, commits or push. Old F and failed/interrupted attempts remain separate and are not used as F2 acceptance.

## Independently verified actual evidence

- Local `android/final-3f1be180`: all **ten** required distinct stages exist in progress, every stage has actual runner exit0, and aggregate is GREEN/accepted with no missing, duplicate or failed stage. This conclusion also checks component originals below, not merely aggregate JSON.
- **115 independent checks pass**, including 74 completed local and 59 downloaded CI process records with recomputed original-log hashes and no timeout, forced cleanup or surviving owned process. Intended Service mutants have exit1; ordinary producers exit0.
- Local and remote arm64-v8a/x86_64 manifests name exact F2 as source and build identity. Actual SO hashes match each run's manifests, contain F2 and no old F identity, and independently parsed ELF matches producer metadata. Source-input file hashes match exact F2 files. Local use of prior build caches did not reuse prior artifacts/verdicts: actual F2 embedded identity, fresh build logs and all output hashes were checked.
- API24 strong imports were **independently re-run with llvm-readelf** on all four actual local/remote Rust SOs and both actual APK JNA JNI libraries, against installed exact NDK28.2.13676358 API24 stubs. All resolve; results equal producer manifests. Rust and JNI LOAD alignment is 16KiB.
- Local and downloaded Linux original logs pass unchanged strict Rust full/JVM six-line/missing-library/panic checkers. Current-source manifests, before/after source inputs and actual libraries/bindings are consistent. No JAVA_TOOL_OPTIONS preamble filtering or checker relaxation was used for acceptance.
- Local shipping Service: four actual JVM variants, current buildIdentity and mapped SO checks; same-run Linux/Service/actual SO and binding cross-hashes; actual probe JAR and independently frozen probe source hash. Reviewer directly re-read and verified all four durable record groups against F2. Seven durable controls actually passed.
- All **three compiled shipping semantic inverses** have actual successful release build logs (including recompiling the host crate), exact unique F2 mutation-source hashes, distinct actual mutant SO hashes, and fresh paired baselines. Each baseline has four-variant exit0. Each mutant has clean exit1 with exactly its intended assertion: dedup/`duplicate_is_existing`, epoch/`stale_epoch_rejected`, join_slot/`slot_held_until_join`. Every original mapped marker matches F2 and the exact actual SO; raw hashes/process records were checked. No unrelated failure is classified as a killed inverse.
- Five private Rust Service targets actually report 4+4+1+2+2 = **13** passing tests. Existing checker controls actually report **71** tests OK; new contract/aggregate controls report **13** tests OK.
- Local and downloaded package original required-Gradle logs each contain **163 actual PASS lines**, actual compileDebugAidl/lintDebug and BUILD SUCCESSFUL. Local packaging reports 81 tasks executed. This supersedes reading the older component-count fields in verdicts as a complete state-test count.
- Both local and remote diagnostic app APKs contain exactly six expected native entries. Reviewer recomputed each byte hash against its own producer/JNI/graphics records, parsed ZIP local-header offsets, required stored compression and 16KiB offsets, checked native ELF LOAD alignment, and independently reran zipalign on all four app/test APKs: exit0. APK DEX bytes also contain F2. Local diagnostic APK SHA256: app `3ed45cf1d8fd22737854dc38a2477f379f188840397ab25613c6ccb805bddcb9`; test `b56883010fb985fe1eb0ef682efb065434865245a143cdcca91ff6f3076c0289`.
- Local retained lint/AIDL inventory hashes match actual files saved before ordinary clean. Lint XML has **0 Error / 0 Fatal / 6 Warning**. Generated IAgentRuntime Java contains the actual Binder Stub and Proxy. The empty structured-parcel declaration output is not counted as an implementation.
- Ordinary local build has actual clean exit0, independent assembleDebug/assembleDebugAndroidTest exit0, 71 tasks executed, current source unchanged, recomputed actual APK hashes/native inventories and **no Rust bridge SO**. Its app retains four expected JNA/graphics natives; no claim that it contains no native libraries at all.

## CI identity and evidence boundary

Downloaded official Android run **39097188799** is completed/success with run/PR head exact F2. Actual select, required-linux, required-android arm64, required-android x86 and required-full jobs and steps succeeded. compiling-red and service-host-checkpoint are intentionally skipped separate modes, not claimed acceptance. Artifact name suffix `6a9c4da...` reflects the PR event merge SHA; actual producer manifests, embedded SO/DEX identity and source input hashes certify F2 and were checked directly rather than inferring from filenames.

Remote package artifact includes successful lintDebug/compileDebugAidl original task logs but **does not retain the lint XML/HTML or generated AIDL Java originals**. Those report/source-output originals were independently checked only for the local same-F2 package run. Do not describe remote lint warning counts or generated Java as independently inspected remote originals.

Android ART, Binder execution, UID/permissions enforcement, Android fsync, kill/rebind, device and emulator remain **NOT_RUN**. JVM durable records do not establish the first actual payload or exact handler count; private Rust observers are separate evidence. No source/version/old-hash grafting, provider/network execution, publication or deployment is claimed.

## Supporting deliverables

- `F2-FINAL-ARTIFACT-REVIEW.json`: local actual records/JAR/SO/bindings/durable/inverse checks, complete=true and all_checks_pass=true.
- `F2-PACKAGE-NATIVE-CI-REVIEW.json`: 69 package/native/CI byte, ZIP/ELF and hash checks, all true; independent zipalign logs adjacent.
- `F2-EXTRA-REVIEW.json`: 21 strict-original, unique-mutation/build, private13, ordinary and independent API24 checks, all true; raw readelf logs under `f2-api24/`.
- Reproducible read-only audit scripts: `audit_final_f2.py`, `audit_f2_packages.py`, `f2_extra_checks.py`.

No Android-scope blocker remains. Generic CI and Claude I04/I05 completion are outside this report and must be assessed separately before any whole-project readiness claim.
