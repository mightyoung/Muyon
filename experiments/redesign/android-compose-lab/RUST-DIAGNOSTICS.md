# Local Rust declaration diagnostic

Settings → 本地 Rust 检查 is the sole active diagnostic entry. The separate execution
RustUiPort remains NOT_CONNECTED: sending, model/attachment and task refresh do not
become available. User drafts/notes are never diagnostic inputs. Results are
Catalog declaration metadata, not business operation success or execution receipts.

MuyonLabApplication owns one coordinator/adapter/worker for the process. Panels
attach presentation leases, and dispose only those leases. Both handshake and
validation use the same admission slot. Dismissal, 15-second display timeout and
Activity/panel recreation do not cancel the synchronous Rust call, release its
slot or queue another call. Only actual worker return/error releases the slot.
Late results are ignored for dead/expired leases; shared busy changes remain
observable. No native cancellation acknowledgment is exposed.

Ordinary Compose builds compile committed Android-generated Kotlin plus the
pinned JNA5.19.1 Android AAR. They do not invoke Cargo, bindgen or Python, and have
empty BuildConfig.MUYON_BRIDGE_SOURCE_SHA. The adapter explicitly reports missing
native input rather than manufacturing a compatible handshake. No binary is
committed. Android installation/load/render/page-size behavior is NOT_RUN.

Optional dedicated packaging uses both properties:

```
-PmuyonBridgeInputs=/absolute/bridge-inputs
-PmuyonBridgeSourceSha=<independently obtained clean current source40SHA>
```

Both absent is ordinary compilation; one alone, malformed/relative/missing root
or invalid lowercase40SHA fails. Before preBuild, Gradle invokes the one
checker-owned stdlib Python validator with an argument vector and the actual
resolved Android JNA AAR. It must return exit0 and exactly BRIDGE_INPUTS_VALID.
The fixed repository paths, strict duplicate-aware manifest, source/build id,
actual two-ABI Rust hashes, binding/config hashes and JNA AAR/JNI hashes are
validated by that shared checker. See docs/design/ANDROID-RUST-BRIDGE-INPUTS-V1.md.
Only <root>/jniLibs is added; AAR supplies JNA once. arm64-v8a/x86_64 are the only
lab native ABIs. keepDebugSymbols preserves both named libraries for exact APK
entry hash verification. minSdk24 and permissions remain unchanged.

Pure stdlib run-state-checks.sh runs all original38 cases plus29 coordinator
cases. Controlled backend tests use latches/manual workers, not sleep ordering;
fakes prove UI lifecycle semantics, not actual FFI. Two new Compose instrumentation
methods are source-only compile targets with explicitly synthetic ports; four
existing methods remain. Their Android runtime has not run.

Generated source/license provenance is recorded with the delivered actual source
hash and the native/checker fresh-generation command; it is not a hand-written
native stub. UniFFI0.32.2 upstream template support retains its generated header.
third_party/uniffi/MPL-2.0.txt is the unmodified upstream v0.32.2 LICENSE from
https://raw.githubusercontent.com/mozilla/uniffi-rs/v0.32.2/LICENSE,
SHA256 1f256ecad192880510e84ad60474eab7589218784b9a50bc7ceee34c2b91f1d5.
No competitor resource/source/license assumption is involved.
