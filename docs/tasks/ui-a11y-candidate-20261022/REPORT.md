# Minimal UI accessibility candidate from merged develop

Branch `task/ui-a11y-candidate-20261022`. Fixed base
`c130008bbc40d78e85d10058030da9da4aca38f0`; source candidate
`708570d59ea51024ee69bb62c97f63380d490f78` (direct child, no branch merge).
Isolated worktree `/workspace/muyon-ui-candidate`; previous shell worktree and
unrelated changes remain untouched. No AGENTS.md in this candidate tree or workspace ancestors.
Only this independent candidate is pushed; no PR creation, main/develop write,
Office/Bot owner-source edit, deployment or real model/search request.

## Extraction and dependency audit

The complete source diff is 3 files,36 insertions/5 deletions:

- `ConversationShell.kt`: headings on actual conversation title/menu groups;
  polite live-region semantics for existing menu failure notice.
- `ShellInputDock.kt`: stable accessible purpose `消息草稿`, preserved while typing.
- `ConversationShellTest.kt`: two additive regression tests, total6 existing Shell methods.

These three file blobs exactly match the reviewed accessibility commit
`043bed97e218bc25202a803aff3c0de1a5da031f`, extracted only as their app-source patch;
none of its old branch history, Host/FFI/lifecycle/business integration or obsolete
handoff claims are imported. Existing send/preview capability gates remain unchanged.
Actual TalkBack spoken output and broader visual acceptance are not established
by semantics assertions alone.

`acfa9d47808ee860369e080820524ca03c900f59` is **not reapplied**: fixed base already
has all three `PdfDocument().useClosing` calls, whose real helper executes
`try { block(this) } finally { close() }`. The same cleanup bug is already fixed.
Reader component and its platform test are already in the base; no unmerged
Reader source dependency or HOLD is required. Candidate Reader device tests use
that base helper, not the previous branch's different equivalent fix.

`RequestCandidates.kt` is byte-identical to base, retaining its existing recursive
Android-compatible JSON comparison. MainActivity, ChatScreen, Runtime, Service,
Rust/Core, generated bindings, configuration and document production sources are
also unchanged. No unverified feature is enabled.

## New verification on this fixed source

All logs below are newly generated for708570; none are inherited test results.

- Real SDK36/JDK17/Gradle8.13 production + complete androidTest Kotlin compilation:
  `:app:compileDebugKotlin :app:compileDebugAndroidTestKotlin`, PASS exit0,
  1m53s,27/27 tasks executed. `evidence/android-compile.log`.
- Separate actual-component harness: `:app:assembleDebug :app:assembleDebugAndroidTest`,
  PASS exit0,1m50s,62/62 tasks executed. `evidence/component-build.log`.
- Real API26 x86_64 software emulator,1080x1920/420dpi/font1.0:
  Shell6 + Reader4 **10/10 PASS**,90.657s, each distinct method status0,
  `OK (10 tests)`, instrumentation code-1. Both component APK installs confirmed
  Success. Logs `evidence/device-install-and-tests.log`, `device-instrumentation.log`;
  exact18 source hashes `component-sources.json`, APK hashes `component-apk-hashes.json`.
  Existing task-owned emulator was stopped after completion.

The harness renders actual byte-identical sources with synthetic UI/PDF and host
fixtures. It is **not** the product APK, and does not prove authoritative ReaderHost/
FFI permission/sidecar persistence. Production ReaderHost remains null and existing
feature downgrades remain. These are device component regressions, not model inference
or enabled business saves.

Offline actual-source checks (`evidence/offline/`): snapshot PASS; canonical JVM
Host/Shell3 PASS groups; Reader state/sidecar/Office text PASS; cards45 PASS;
configuration5/5 PASS with all actual source dependencies; Bot17 PASS;
palette contrast1 PASS; Android package-checker unit tests PASS.

Two original external-runner failures are explicitly retained:

1. `host-shell.log`: additional2013 Android JSON fork artifact exposes raw
   `Iterator`, inferring Any? keys, incompatible with base's correctly Android36-
   compiled comparator. Retested unchanged sources with the runner's intended
   official JSON-java20250517 JVM artifact, PASS in `host-shell-canonical-jvm.log`.
   This JVM check complements, and does not replace, actual Android compilation.
2. `configuration.log`: existing configuration script omits existing
   `SetupDraftArchive.kt`, producing unresolved archive types in BotSetupDraft.
   No owner file/script was edited. External `configuration-full-inputs.sh` includes
   that real source and runs the same original checks,5/5 PASS. Original script
   remains defective on this base and must not be described as passing.

## Real product packaging continuation

The first actual product assembly attempt without inputs failed at existing
`verifyModelAssets` (`evidence/product-before-inputs.log`). Parent then authorized
reuse of the base's actual fixed CI model provisioning, not fake test models.
Read `.github/workflows/muyon-product.yml`, `checks/ci_model_inputs.py`,
`prepare-model-assets.py`, fixed model manifest and packaged NOTICE first.

Both actual `ci_model_inputs.py <task-source> <task-assets> --fetch` and repeat
without `--fetch` succeeded,6 verified offline assets (`model-provision.log`,
`model-offline.log`, `model-manifest.json`). The309855456-byte GGUF, pinned OCR
ONNX/configs and generated dictionary are real fixed assets. Credential-free
public fixed HTTPS sources and pinned license/model-card notices were fetched
using the unchanged repository script; no login, paywall or extra agreement arose.
No inference was run. The packaged legacy provenance is retained; the separate companion notice corrects
the upstream-declared source revision using fixed .src_sha/LFS records, while
conversion orchestration remains unreproduced. Artifact hashes do not prove additional distribution rights.

Official Rust1.93.1, Android targets, locked Cargo dependencies, NDK28.2.13676358
and CMake3.22.1 were recovered under `/workspace/ui-shell-tools`. NDK/CMake
repository entries reference the same already accepted `android-sdk-license`.
No sudo, HOME/proxy/network/security change, persistent credentials or extra CI.
Initial CLI shorthand `ndk@...`/`cmake@...` reported no URL and installed nothing;
exact official package identifiers `ndk;28.2.13676358`/`cmake;3.22.1` succeeded.

Host binding build initially failed to find `-lsqlite3`: this environment has the
real system `libsqlite3.so.0` but lacks the unversioned development link. A task-only
link to that existing real library and process-local LIBRARY_PATH resolved linking;
no replacement library or stub was used. Original error is preserved. Generation
also initially lacked process PATH/required crates working directory; corrected
commands followed the existing CI. Generated Kotlin binding comparison passed
without modifying checked-in bindings.

## Final product APK result

**PASS** complete clean offline product build:
`:app:clean :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug`,
2m17s,78/78 tasks executed,exit0. Exact env/properties/arguments are archived in
`evidence/product-command.json`, terminal log `product-final.log`, exit file
`product-final-exit.txt`. Existing fixed model/native/source-identity checks all ran.

The first combined attempt produced the actual APK but then failed to resolve
`com.android.tools.lint:lint-gradle:31.11.1`; original failure retained in
`product-first-lint-missing.log`.32 official fixed Lint artifacts were restored
from Google Maven/Maven Central to the same task-local offline repository,
recorded hashes/sizes in `lint-dependency-provenance.json`. `lintDebug` first
passed separately (`lint-first-pass.log`); then the entire clean build above was
repeated and succeeded. No proxy/security changes, disabled check or fake artifact.

Final **product**, not component-preview APK:

- Source `708570d59ea51024ee69bb62c97f63380d490f78`.
- Application `com.mightyoung.muyon.product`, label Muyon,debug version0.1.0,
  minSdk26,targetSdk36, `arm64-v8a` and `x86_64`.
- Size **426369208 bytes**.
- SHA256 **`f1cc240fd981a1ea08841f3964c6422e5b240268984447022406428723ddeb0b`**.
- Final `package_gate.py` PASS: exact generated Kotlin bridge, real product/native
  library bytes, both ABIs/ELF architecture/16KiB alignment, no hidden SQLite dependency.
- Final `model_package_gate.py` PASS: all6 actual model/config/dictionary bytes,
  ten model/runtime/provenance notices and packaged library checks.
- SDK `apksigner verify --verbose --print-certs` PASS; ordinary Android debug signer,
  not a release signing claim. SDK `aapt dump badging` confirms product identity,
  minimum API and ABI set. Raw JSON/logs are `evidence/package-final.json`,
  `model-package-final.json`, `product-signature.log`, `product-badging.log`.

Build identity:
`708570d59ea51024ee69bb62c97f63380d490f78:95d79703ba3b05f9af3020118286fb5559f17c7042d183cee394074dc25ae811`.
Actual final instrumentation APK SHA/size are separately in `product-apk-hashes.json`;
its successful assembly/compilation does not imply full product device execution.
No product APK/model inference was run, and no full product authorized ReaderHost/
FFI/sidecar persistence acceptance is claimed. The component10/10 run is separately
labelled above. Feature gates and service/core ownership remain unchanged.

## Licence companion and delivery preparation

[MODEL-LICENSE-NOTICE.md](MODEL-LICENSE-NOTICE.md) supplies human-readable attribution,
18385-item Muyon-generated dictionary derivation from fixed PaddlePaddle rec.yml,
and the upstream-declared Google source revision correction. This extra provenance
document does not alter model bytes, fixed thresholds, sources or the APK's inherited
notices. Full existing notices/cards/licences remain packaged byte-identically;
all APK `assets/notices/*.txt` are also copied verbatim into the prepared bundle.

Task-owned delivery folder and ZIP are recorded in `evidence/deliverables.json`.
The ZIP includes the actual source-labelled product APK, readable companion,
model manifest, full notice texts, verification summary and SHA256SUMS.
**Prepared only: no Library upload, publication or user delivery performed.**
Parent explicitly decides delivery timing; this result is supplied for that decision.
No APK/model bytes are committed to Git.

## Review, integration and remaining limits

Independent review verified source scope,18 pinned component inputs, new10/10
instrumentation results and original failure retention. Final review additionally
checked six real assets, independently regenerated the dictionary in memory,
verified the upstream source/LFS/quantizer record and final product build/gates.
Its exact closure is [INDEPENDENT-REVIEW.md](INDEPENDENT-REVIEW.md).

The model/toolchain packaging blocker is resolved for this fixed candidate.
Remaining limits: complete product runtime/permission/inference acceptance NOT_RUN;
original configuration offline runner still omits Archive input (corrected external
command passes same5 tests); optional2013 JSON fork has a raw-iterator signature
mismatch (standard JVM checks and actual Android36 compilation pass). Real TalkBack
speech, expanded visual acceptance and still-disabled business capabilities remain
outside this batch. No claim that all UI/product development is complete.

Parent/B may consume the **single source commit708570** onto develop; this branch
contains no old Shell merge or new native/Host source. Only parent organizes PR and
B performs integration. main/develop were read-only throughout this task.
