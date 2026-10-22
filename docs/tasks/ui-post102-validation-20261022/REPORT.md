# Post-PR102 actual product validation — fixed c804

Exact product source `c8044174a37fdc0e4d807307f81fc56a7cc74232`, B's fixed
`lab/post-pr102-ui-a11y-20261022` head, read from remote and checked out directly
in `/workspace/muyon-ui-post102`. Contains PR102 base4cbc plus the reviewed UI slice.
The three UI source blobs match708570, but **all build/runtime evidence is new**.
B branch, PR103, main and develop are never written. Own documentation-only branch:
`task/ui-post102-validation-20261022`; shipping source remains c804.
No AGENTS.md in the fixed candidate tree/workspace ancestors. No production source
changes, credentials, elevated rights, deployment, model/search requests or inference.

## New actual builds and static package gates

Official existing task-local SDK36/NDK28.2.13676358/CMake3.22.1/JDK17/Gradle8.13,
Rust1.93.1/Android targets and locked caches were reused. Fixed model provisioning
was repeated **offline** with the actual new repository script; all6 real assets
verified. Model provisioning/NOTICE sources are unchanged from previously verified
fixed inputs; no new terms, model credentials or paid source was involved.

Actual `build-native.sh` built both real product and embedding libraries for
arm64-v8a/x86_64. Host build with bindings feature succeeded; uniffi-bindgen generated
current Kotlin into a task directory, and strict `cmp` to checked-in bindings passed.
The genuine system SQLite development link in task-only LIBRARY_PATH was reused,
not a substitute Android library. Existing native/ML/model input gates remain intact.

New complete clean **offline** command:
`:app:clean :app:assembleDebug :app:assembleDebugAndroidTest :app:lintDebug`.
**PASS exit0,3m36s,78 tasks:77 executed/1 up-to-date**. Both main and complete
androidTest Kotlin compilation executed. Exact arguments/environment/source identity
are in `evidence/product-command.json`; raw terminal log `product-build.log`.

Both `package_gate.py` and `model_package_gate.py` passed on the actual APK,
including exact native/generated-binding bytes, two ABIs, ELF/APK16KiB alignment,
six real model/config/dictionary files and ten complete model/runtime/provenance
notices. Official apksigner verify passed; ordinary Android debug signer.
SDK badging confirms product application, minSdk26,targetSdk36,two ABIs.

Actual product artifact (not component preview):

- Application `com.mightyoung.muyon.product`,version0.1.0/debug.
- **430153912 bytes**.
- SHA256 **`bf54a74d7df4d0f2f48d59be7d9608d26f813b1d20494d8e7538218b49ff6841`**.
- Native identity
  `c8044174a37fdc0e4d807307f81fc56a7cc74232:192689c72a496283f788e341516b179893824efef62f8bc113c220616cbbdda5`.

New offline checks: snapshot/Host-Shell/Reader/cards45/Bot17/contrast/package checker
PASS. Original configuration script still fails because it omits existing Archive
source; raw failure retained. External full actual-input command runs the same5
configuration checks and passes5/5; no owner source/script was edited.

## Acceptance gates and runtime

Product Service `verified=false` remains unchanged; unavailable persistent saves,
authoritative ReaderHost/PFD/annotation gates are not opened. Including PR102 code
is not proof of complete Office/Bot workflows. Actual minimum runtime smoke and
its precise additional limits are recorded below once completed; old708570 runtime,
component10/10 and screenshots are never reused as c804 results.

## Actual product smoke / environment exception

New430153912-byte APK installed successfully as com.mightyoung.muyon.product,
version0.1.0/debug. On-device base.apk SHA256 exactly equals bf54a74d7df4d0f2f48d59be7d9608d26f813b1d20494d8e7538218b49ff6841.
Fresh task-owned instance, account count0; no user files or external account used.
Cold launch Status:ok6096ms at20:06:55; reentry Status:ok3031ms.

Initial UI capture was BLOCKED by exact window `System UI isn't responding`,
package android. ActivityManager identifies com.android.systemui PID1739 at
19:57:36, executing .SystemUIService; android.process.media PID2141 at19:58:14
USB_STATE/MtpReceiver timeout. Both precede product start20:06:55. No permission
request accepted, no product ANR/FATAL observed in retained log. A single normal
system Wait restored UI, without changing emulator settings. This is a qualified
software-emulator result, not an uninterrupted cold-boot claim. Rejected PNG/XML
and full raw log retained.

Local create-workspace clicked exactly once. First post-init hierarchy check
failed `null root node`, retained. Later read confirmed actual initialized empty
state; initialization was not retried. Actual main/menu PNGs inspected. Menu
explicit close, second menu/back close, Back to Launcher and actual MainActivity
reentry succeeded. No message/search/provider/model/Reader-policy action performed.
API26 x86_64 software emulator1080x1920,420dpi,font1.0,dark system theme.
Screenshots are genuine product empty-state runtime, not synthetic conversations
or component-harness output.

## New device and service tests

Original Shell6 + Reader component4 + external read-only real Service health1:
**OK(11 tests),96.77 seconds**, terminal instrumentation code-1 (success).
Shell/Reader methods use component fixture content, not real document authorization.
The separate Service probe calls only health and agent_availability: native exact
c8044174a37fdc0e4d807307f81fc56a7cc74232:192689c72a496283f788e341516b179893824efef62f8bc113c220616cbbdda5,
synthetic=false, configured=false, chat/search transport_bound=false.
This does not open or validate model, search, controlled Reader, save or Office/Bot
production workflows. Probe is external test-only source, not shipped product code.
Actual source AndroidTest output restored from preserved exact original, while
probe APK remains separately identified outside git.

Small license companion contains11 exact APK notice files plus the accurate
derived-dictionary/source-revision correction; no duplicate APK inside ZIP.
All delivery hashes/sizes are in DELIVERABLES.json. Library status recorded separately.

## Library delivery BLOCKED (not uploaded)

One current official Library helper invocation attempted the ordered4-file batch:
new APK, small license-only ZIP, main PNG, menu PNG. Helper exited1 before any
prepared file mutation: `hosted apps tools/list request failed with HTTP status401`.
Stdout is empty. This is authentication failure at tool discovery, not a size
rejection, not a safety denial, and not an uncertain finalized upload. No Library
file ID exists for these files. No retry, direct-route substitute, credential
configuration or public hosting was attempted.

Target files remain ready in `/workspace/ui-shell-tools/post102/delivery/`; their
exact sizes/hashes are in DELIVERABLES.json. Re-enable authenticated Library helper
access in this execution environment (or an authorized consumer with actual file
access) before the upload can proceed. There is no duplicate430MB ZIP. Old708
APK was never uploaded. Parent chooses final delivery timing/merge independently.

Follow-up material correction: license ZIP now self-contained with model-manifest
and original upstream .src_sha/LFS/convert-log evidence,47379 bytes,SHA256
dd47422ea8823d215cebd63b0f3c01a31d352e9083b65c6c414e869c02b4c878.
No further Library attempt was made; APK/PNG bytes are unchanged.

Independent review: INDEPENDENT-REVIEW.md. Raw terminal logs intentionally retain
original trailing whitespace; diff--check reports those raw-evidence warnings,
not a production code change.

## Authorized Library connection follow-up

Parent supplied materially new evidence of a working official Library connection
and explicitly authorized one new minimum read probe and helper attempt.
Official Library list(`/`,recursive=false,include_folders=false,limit=1) PASSED,
returning owned libfile_233e54fda540819189a2ce911b5153af.
The required prepared-upload helper was then invoked once with the same ordered
APK/license/main/menu paths; it again failed at hosted apps tools/list HTTP401,
stdout empty, before prepare/transfer/finalize. No upload IDs exist. Stopped here;
no credential reading/configuration/export, direct fallback or further retry.
Thus official read access works while this execution environment's helper
authentication remains blocked. Builds and artifact bytes were not rerun/changed.
