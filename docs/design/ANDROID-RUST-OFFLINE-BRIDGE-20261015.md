# Android ↔ Rust: bounded offline declaration bridge

2026-10-15. No product/source changes or build performed for this proposal. Native host author tree is clean at5fc2b42b33901123e3f832e4458666ef5fecee0c. UI owner confirmed clean source2b0ed6441fa8a785bbddfff59e2e6b301ea3ff10 in its separate Android clone; root is integrating PR80/79 independently. These identities describe inspected sources, not a new integration or merge result.

## Recommended first slice

Connect one real stateless Rust FFI diagnostic to the Settings-only Local Rust Diagnostic panel: native capability handshake plus validation of one built-in Rust read declaration. It invokes the actual existing Rust mappings and Catalog registration/inspection, not a Kotlin reimplementation, canned success or fake business read. Show the result in an independent native-engine diagnostic panel. Do not append it as an assistant answer, task completion or successful read receipt.

This is a useful first real Android/Rust dependency boundary with no new Linux-host transport refactor. A full offline Agent/read integration is a separate next slice, explicitly not proved by loading a shared library or validating metadata.

## Current seams and limits

- Native host `core/src/lib.rs`: NativeSession::create requires a plugin executable Path and immediately spawns PluginProcess; RuntimePorts/ModelGateway reuse the common Agent drive. Rc<RefCell<NativeSession>>, authority/review/handler trait objects are thread-local, not a Send/Sync UniFFI object.
- `plugin_process.rs`: owned std::process child, Unix fd/fcntl with Linux constants, pipes, kill/reap and absolute executable path. There is no packaged Android contract-child binary, Android lifecycle adapter or verified Bionic/SELinux/package loading behavior. Copying the Linux binary or calling this constructor from JNI is not an Android port.
- NativeStore/core store use Unix private-directory checks, flock/geteuid, atomic file and directory fsync; their Linux tests are not Android app-filesystem evidence. Current NativeStore is a65536-byte experimental receipt snapshot, not the Android product database.
- Plugin library already exposes pure Rust mappings::{declaration,renamed_equipment} and Catalog::{new,handle}. They can serve the no-I/O diagnostic without invoking Agent, process, file storage or models. Existing core dependency still must actually cross-compile/link on each selected Android target; source-level reasoning alone is insufficient.
- UI `ShellState.kt` exposes only synchronous availability()==NOT_CONNECTED. `MuyonLabShell.kt:40` caches that once with remember(port). A real adapter must publish observable state; adding a new enum variant while retaining that cache does not implement a dynamic handshake.
- SPIKE-01 provides an existing UniFFI0.32.2/JNA5.19.1 design and Linux JVM real FFI, Kotlin/D8 and two Android ELF build evidence. Android actual load is explicitly NOT_RUN; callbacks/lifetime tests are experimental and not native-host APIs. Reuse its pinned build/bindings approach, not its old prebuilt libraries or LabSession as product authority.
- Current UI minSdk24 vs old spike link/min-api26 is a concrete mismatch: build the new bridge/JNA package against the UI's accepted floor and verify dependencies, or report a blocker. Do not silently raise minSdk or reuse26 artifacts as proven24 support.

## Frozen private first-slice contract (C1/C2 corrected)

Protocol1 is private to this experiment, not public M03. Package is
`muyon-android-contract-bridge-lab`, Rust crate/library and UniFFI namespace are
`muyon_android_contract_bridge`, native library is
`libmuyon_android_contract_bridge.so`, generated Kotlin package is
`com.mightyoung.muyon.androidbridge`. Both shipping functions below are global,
stateless functions; no session object, callback or observer is exported.

```rust
pub enum DiagnosticCapability { BundledDeclarationValidation }
pub enum DiagnosticVariant { Equipment, Research, Inquiry, SeededEquipment }

pub struct BridgeInfo {
    pub protocol: u32,
    pub build_identity: String,
    pub capability: DiagnosticCapability,
    pub model: bool,
    pub attachments: bool,
    pub business_read: bool,
    pub write: bool,
    pub execute: bool,
}
pub struct DiagnosticRequest {
    pub protocol: u32,
    pub request_id: String,
    pub variant: DiagnosticVariant,
}
pub struct DiagnosticReport {
    pub protocol: u32,
    pub request_id: String,
    pub build_identity: String,
    pub variant: DiagnosticVariant,
    pub namespace: String,
    pub catalog_generation: u64,
    pub data_count: u32,
    pub operation_count: u32,
    pub relation_count: u32,
    pub view_count: u32,
}
pub enum BridgeError {
    UnsupportedProtocol,
    InvalidRequestId,
    DeclarationRejected,
    InternalFailure,
}
pub fn bridge_info() -> BridgeInfo;
pub fn validate_bundled_contract(
    request: DiagnosticRequest,
) -> Result<DiagnosticReport, BridgeError>;
```

- `protocol` must equal1. `request_id` is exactly `[A-Za-z0-9_-]{1,64}`,
  auto-generated internal correlation data, never user draft/text. Protocol and ID
  validation precede mapping/registration. The report echoes protocol/request ID/
  variant exactly. SeededEquipment uses fixed Rust seed0x7631; Kotlin supplies no
  arbitrary schema, seed, path, authority, grant or operation arguments.
- `bridge_info` returns capability BundledDeclarationValidation. The five
  operational booleans are alwaysfalse, a static declaration of this narrow
  bridge's surface, **not measurements or global permission/revocation state**.
  Only actual native loading plus compatible handshake enables the separate
  diagnostic availability. Packaging an .so does not enable it.
- Rust obtains the actual built-in ReadDeclaration, registers it in a fresh
  Catalog and reads real generation/DATA/operation/relation/view counters from
  inspect. Counts mean declarations checked, never executable tools. Report has
  **no grants, receipts_created, execution_requests or handler counters**.
  Catalog inspect's grants/receipts fields are constantzero, and its executions
  counts invoke-dispatch requests rather than handler executions; none is used
  as a diagnostic measurement. Source/call-path checks establish that this
  diagnostic installs no handlers or receipts and calls no model/store/child.
- `catalog_generation` is the actual u64 generation. Counts are checked u32
  conversions of actual Catalog replies; malformed/missing/overflowing inspect
  fields produce InternalFailure, never guessed zero. `namespace` is derived
  from the admitted declaration, not from Kotlin labels.
- `build_identity` is the full clean40-character source Git SHA supplied by the
  reproducible build script as `MUYON_BRIDGE_BUILD_ID`; required at compile time,
  validated by the build script. An external CI artifact manifest associates
  this identity with source tree/archive, librarySHA256 and generated binding
  SHA256 (plus ABI/toolchain). The identity is not the library's own digest or a
  signature, runtime counter or proof of business capability. No self-referential
  library hash is embedded. JVM/packaging gates compare the manifest and actual
  loaded library/binding provenance.

BridgeError has four unit variants, without arbitrary reason/stack/path payloads.
Stable internal display tags are `unsupported_protocol`, `invalid_request_id`,
`declaration_rejected`, `internal_failure` respectively. A Catalog register
rejection maps to DeclarationRejected. Unexpected mapping/inspect/invariant
failure maps to InternalFailure. Kotlin keeps separate adapter states
NativeUnavailable(Load), NativeUnavailable(ProtocolMismatch), RequestMismatch,
Busy, NativeFailure. Linkage/generated-binding/panic errors never become success
or business receipts, and unknown raw reason strings are not shown.

## Cancellation/lifecycle and actual single-flight ownership (C2)

There is no native cancellation acknowledgment. Rust executes one finite
synchronous metadata check. Kotlin invokes it off the main thread through one
**application-process shared RustDiagnosticCoordinator**, independent of panel
or ViewModel instances. `tryStart` returns Accepted(token) or Busy; there is no
unbounded queue and no automatic retry.

The coordinator acquires its single-flight slot before starting native work and
releases it only in the worker's finally block **after the actual synchronous FFI
function has returned or thrown**. Panel dismissal, timeout, ViewModel clearing,
coroutine cancellation, rotation or panel reopening invalidate only presentation
request_id/generation. They must not release that slot, spawn another worker or
queue a replacement. A reopened holder shares the same coordinator and remains
Busy while the original call runs. Once it really returns, its stale result is
ignored, the slot becomes available, and a new explicit request may start.

The worker is bounded to one in-flight task. Native code exports no session,
observer, callback, file/socket/child resource or persistent state; Catalog and
temporary buffers drop on return. UI readiness is observable rather than a
one-time remember(port) availability snapshot. Existing conversation drafts,
scroll/local records and operational controls remain separate; no diagnostic is
stored as a chat message, task completion or receipt.

## Exclusive implementation ownership

| Owner | Exclusive directory/change |
| --- | --- |
| Original native-host writer | New experiments/redesign/android-rust-bridge-lab/core: rlib/cdylib, typed FFI façade and tests, depending on existing plugin crate; no edits to Linux NativeSession/core/plugin needed in this first slice |
| Original UI writer | Existing android-compose-lab state/app: native adapter, observable diagnostic state holder, Settings-only diagnostic/result panel, generated binding integration and jniLibs packaging under its directory |
| Existing checker | New bridge-specific check harness/workflow; Rust/Linux JVM native-call/Android cross-link/Compose assembly evidence separately labeled |
| Existing independent reviewer | Small contract/FFI/cancellation/error/resource review, then fixed-source check; no new competing writer |

Use the existing pinned UniFFI/JNA approach and normal approved CI tool setup. Only the new bridge crate needs FFI build dependencies; do not pull them into core Agent or Catalog, introduce Dart, create a new Agent loop or widen permissions. Generated files/artifacts need exact source/library/binding hashes and reproducible generation, not manual Kotlin stubs claiming Rust execution.

## Test-first delivery and evidence gates

1. Freeze only this bounded private DTO/capability/error/presentation contract. Write a real Rust bridge refusing implementation with a reachable marker and positive metadata-validation assertion; compile and observe semantic RED. Unsupported protocol/id plus valid siblings must be single-cause checks.
2. Generate bindings and compile the real Linux cdylib. Linux JVM calls those generated bindings and receives an actual Rust error/marker before any Kotlin success path exists. Then implement the façade and require actual register/inspect-derived generation and declaration counts. No grant/receipt/handler counters are exported or inferred. A Kotlin mock state test is not native-call evidence.
3. Add the Kotlin observable adapter/state tests: load failure/protocol mismatch, actual compatible handshake, bounded request id, exact request correlation, stale-result ignore, local dismiss without fake cancel acknowledgment, cross-panel single-flight until the real synchronous return, no task/chat insertion, model/attachment/execute stilldisabled. All UI-memory regressions remain required.
4. Cross-compile new .so for arm64-v8a and x86_64 at the unchanged Android API floor, package matching JNA JNI assets, inspect ELF target/segments and hashes, and run normal Compose/app/test-APK assembly. Old26 spike artifacts are not sufficient. No app install, emulator/device access, new license acceptance or credential needed/authorized here.
5. Report Rust, actual Linux JVM FFI, Kotlin state, Android cross-link, Gradle assembly and Android actual execution as separate outcomes. Android load/lifecycle/4KB16KB runtime, display fidelity and product behavior remain NOT_RUN until separately authorized platform execution. Do not call the assembled UI capable of business reads.

## Subsequent full native read slice, explicitly deferred

If root later wants the actual Agent/read pipeline inside Android: first add an internal ContractTransport seam in native host with existing PluginProcess implementation unchanged, and a separately tested in-process Catalog implementation consuming the same bounded envelopes. Reuse the same Agent drive, handlers, live authority/purpose checks and receipts. In-process admission is not a child-isolation proof.

That next slice also needs an app-private filesystem root and Android storage evidence, a narrowly controlled worker owning the current non-Send session, and an independent cancellation signal that cannot sit behind a busy request in the same queue/mutex. Any exported session requires typed terminal status, pending cancellation distinct from final acknowledgment, close/drain/lifetime tests, late-result suppression and no auto-resend after unknown receipt. Current SPIKE callbacks demonstrate some FFI hazards but do not supply these native-host contracts. No need to resolve that larger actor/storage/transport work to land the first real stateless offline bridge.

UI owner alignment: display counts as "已检查N项声明", never "N工具已可执行". No grants/execution/receipt counts are returned. Disabled capability flags describe only this bridge surface, never global permission or revocation state. Do not transmit LocalUiState drafts into the diagnostic. Stable adapter errors are Load/Protocol/RequestMismatch/NativeFailure with no raw stack/reason passthrough. Original writers implement only their exclusive directories after root records successful integration gates and activates the tasks in the linked plan.


## Locked build surface and panic-boundary tests

New Cargo.toml belongs only to android-rust-bridge-lab/core. `[lib]` uses name
muyon_android_contract_bridge and crate-type `["rlib", "cdylib"]`. Necessary direct
runtime dependencies are existing path `muyon-plugin-contract-lab` and pinned
`uniffi = "=0.32.2"`. BridgeError can implement Display/Error directly with the
four static tags, so no direct serde, serde_json, sha2, unicode-normalization,
thiserror, JNI, HTTP/model or Dart dependency is needed. A `bindings` feature may
activate `uniffi/cli` for a local uniffi-bindgen binary following the existing
spike pattern; the generated bindings are not hand-written. Commit the new
Cargo.lock including the CLI/derive/runtime transitive resolution and build with
--locked. It is not a copy of the entire spike crate, whose unrelated domain
normalization/digest dependencies are unnecessary.

Use the existing validated UniFFI/JNA candidate pins; JNA5.19.1 is an app dependency
and matching JNI ABI packaging asset, not a Rust Cargo dependency. NDK/API24 and
both Android targets must be actually built/linked, and versions/hashes recorded.
Do not infer new bridge/toolchain compatibility merely from host Rust1.90 unit
results, nor reuse old API26/JNA/native binaries without checks. Missing approved
tools/ABI compatibility is a build blocker, not permission to accept licenses,
install a device runner or raise the API floor silently.

Release profile explicitly uses panic="unwind". The bridge's private validation
boundary catches Rust unwinding and returns the closed InternalFailure; UniFFI's
own FFI boundary remains responsible for generated-call conversion. Rust unit
checks inject a harmless fixed synthetic panic through the same private wrapper,
assert the typed failure, and then perform a valid call to prove no poisoned
shared/native session state. A separately enabled test-only Linux cdylib feature
`ffi-test-probes` may export a fixed synthetic panic probe to exercise actual
JVM/generated-binding panic/error conversion and subsequent successful native
call; it is off by default and absent from Android/shipping exports. Its separate
source/library/binding hashes must be recorded rather than substituting the
probe artifact for the app artifact. No synthetic panic variant is added to the
shipping request enum and no arbitrary text/code execution hook is exposed.

Single-flight state proof uses a controllably blocked fake native port: first
entry, dismiss/timeout/holder clear/reopen, rejected second start, max native
entries1, release first, ignore stale result, then accept a new explicit call.
That test proves coordinator behavior only. The separate Linux JVM test must load
the actual generated native library and validate all four variants/errors; mocks
and cross-compiled Android ELF alone never count as an Android runtime result.

Binding/config/committed-source ownership and source/library/hash reproduction details are fixed in the companion android-bindings-reproducibility-note.md. In particular0.32.2 --config uses global [crates.muyon_android_contract_bridge.bindings.kotlin] overrides, not a flat per-crate table supplied as a CLI override. The normal Compose lane may compile committed Android generated source without a Rust binary; actual bridge CI independently regenerates/compares and explicitly packages both ABI libraries.

## Integration and build contract

Implementation is the already-authorized minimum Android/Rust wiring, activated only after root finishes the reviewed PR80/PR79 integration into develop. This is a bounded extension of the existing disconnected UI capability seam, not a full Android port of NativeSession and not a new public M03 interface. Root is sole integrator and pusher. Original owners and histories remain preserved.

Commit reproducibly generated Android Kotlin bindings as source, retaining generated/license headers; no native binary or raw verification log enters Git. Normal Compose compilation requires no local Rust compiler: the bindings plus Android JNA dependency compile, and absent Rust library remains explicitly unavailable at runtime. Dedicated bridge CI generates the Android bindings again and byte-compares; Linux JVM uses separately freshly generated desktop bindings. A native-ready diagnostic requires actual successful native handshake, never source inclusion or a Kotlin mock.

Pin UniFFI0.32.2 and JNA5.19.1. Commit separate Android/JVM global override TOMLs using [crates.muyon_android_contract_bridge.bindings.kotlin], matching package and library names; Android android=true/android_cleaner=true, JVMfalse. Generate with --crate muyon_android_contract_bridge --config <matching-global-TOML> --no-format. Do not pass deprecated flat [bindings.kotlin] as a global --config or invent a jna=true switch. Generated source contains no source SHA literal, avoiding a self-referential commit; external build manifests bind source/library/binding SHA identities.

Keep Android minSdk24, compile/target36 and existing app permissions. New Android libraries must actually cross-link for arm64-v8a and x86_64 at API24 with NDK28.2.13676358, matching JNA Android AAR assets; desktop JNA JAR is only for Linux JVM evidence. Normal app build without Rust inputs remains disconnected. The bridge package build requires explicit source-matched two-ABI inputs and manifest validation before Gradle packaging. Inspect both Rust and JNA ELF/LOAD alignment and packaged hashes, plus API compatibility/lint. Android execution/page-size runtime remains NOT_RUN.

Existing executing RustUiPort remains NOT_CONNECTED; separate observable Rust diagnostic state can be ready. No network permission, model endpoint, arbitrary declaration/path/authority, new Agent loop or actual business record access is introduced.

Private build paths: core/uniffi.android.toml and core/uniffi.jvm.toml set package_name="com.mightyoung.muyon.androidbridge" and cdylib_name="muyon_android_contract_bridge" in the global per-crate Kotlin profile. Generated Android source is owned by UI under app/src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt. Rust owner may generate to private/tmp and hand off a fixed hash; only UI writes its product source.

The optional Gradle property -PmuyonBridgeInputs=/absolute/bridge-inputs supplies bridge-inputs.json plus jniLibs/{arm64-v8a,x86_64}/libmuyon_android_contract_bridge.so. When present, -PmuyonBridgeSourceSha=<expected-current40SHA> is required and must match the manifest, committed binding/config identities and actual library hashes; missing/mixed/stale ABI data fails before packaging. Without inputs, no Rust library is fabricated and diagnostic availability remains closed. Preserve exact ELF content for evidence with keepDebugSymbols for **/libmuyon_android_contract_bridge.so and **/libjnidispatch.so; JNA libraries come once from pinned Android AAR, never the JVM JAR. Limit this lab's native ABI filters to arm64-v8a and x86_64.

The Gradle native-input/source-SHA properties are paired: both absent means normal disconnected compilation; exactly one present is a setup error, not an ignored option. Add only the validated <inputs>/jniLibs directory as the native source directory, never the entire input root. CI supplies expected current source SHA independently of the manifest being checked.

Only Settings 本地Rust检查 may actively initiate this FFI; the input capability sheet adds no native-call entry. Coordinator admissions are linearized under its lock, but no FFI, worker body or user/listener callback executes while that admission lock is held. A blocked worker must not prevent Busy/detach/expire from completing promptly.
