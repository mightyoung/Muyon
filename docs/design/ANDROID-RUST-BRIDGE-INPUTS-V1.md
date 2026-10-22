# Android Rust bridge-inputs.json version1 packaging contract

Canonical field shape is docs/design/ANDROID-RUST-BRIDGE-INPUTS-V1.schema.json (SHA256 1e47b50edc6e85e352e5d931e10c7a1ef18f0b4b85b112e17bf71664c4a1bece). The planning example uses placeholder source/library/binding hashes, not execution evidence. Zero source/library/binding hashes in example are ONLY
placeholders, never built artifacts/evidence. Constants JNA hashes are frozen
SPIKE officialAAR-byte inputs, verified afresh by producer/consumer against actual
pinned dependency. This schema is the frozen private packaging shape; it is not runtime attestation.

Required top-level keys EXACTLY: format_version, source_sha, build_identity,
protocol, namespace, android_binding_sha256, android_config_sha256, min_api,
rust_libraries, jna. Every nested object likewise has exact schema required keys;
unknown/missing keys, duplicate keys, null, wrong type and trailing JSON are invalid.
Numbers are integers (not strings/bools/floats). Strings/hashes use exact schema
constants or lowercase40/64hex patterns. JSON key order is insignificant to
validation; producer emits sortedkeys/indent2/UTF8/LF for stable artifact bytes.
No RFC8785/business canonicalization/publicM03 claim is introduced.

format_version1 is this packaging envelope; protocol1 is the separate private
FFI contract. namespace is FFI component muyon_android_contract_bridge, not the
variant's Catalog namespace. min_api24 is declared build configuration, NOT
runtime measurement. source_sha is the full clean build source Git40SHA, and
build_identity is the exact MUYON_BRIDGE_BUILD_ID supplied to compiler. Redundant
build_identity is retained solely for direct handshake/producer alignment.

Normative equalities outside portable JSONSchema: source_sha==build_identity==
independently supplied -PmuyonBridgeSourceSha. CI derives the latter from checked-
out git HEAD, never manifest self-claims. New producer records source/artifact
manifests for both ABI builds, validates each same-source shipping profile before
aggregating, and emits this manifest only after actual cross-link/ELF checks.
Consumer independently hashes current committed Android generated Kotlin and
core/uniffi.android.toml and compares the two hash fields. These paths are fixed
by root spec, not selectable from manifest. No currentSHA/time/absolutepath in
committed generated source is needed or allowed.

rust_libraries has exactly arm64-v8a and x86_64; each object contains only path and
sha256. Paths are exact constants jniLibs/<ABI>/libmuyon_android_contract_bridge.so.
Resolve known paths below the explicit absolute input root; require regular files,
exact file set and actual byte hashes, reject missing/stale/extra native payload.
The root contains bridge-inputs.json + jniLibs with ONLY those two Rust libraries;
JNA binaries do NOT go into this jniLibs staging source directory.

jna contains version5.19.1, official Android AAR sha256 and jni_sha256 object for
exactly the same ABIs. JNI paths are implicit fixed AAR entries
jni/<ABI>/libjnidispatch.so, not caller-chosen filesystem paths. AAR hash is
b57125cb7d16253f0d65a80f7d3a4c3664effa711b8bdbb7f87fb572ce1624ed;
arm64 JNI abc26e994517bcaa3309acdb0a27373864086c7569c89d3087b8626fada9ef06;
x86_64 JNI 3809247e9b804a05ed8377b87d545cf5b5e97f960f75e725bc8497b40260e417.
Producer and Gradle consumer verify actual resolved AAR and extracted entries,
not manifest constants alone. The AAR supplies those JNI libraries exactly once.
Use keepDebugSymbols both library names and verify APP APK uncompressed entry
hashes against actual Rust/AAR bytes; no implicit strip transformation is accepted.

NDK/Rust/Kotlin/JDK/Gradle/tool executable hashes, Cargo.lock hash, compiler/API
commands, shipping/probe features, ELF checks, JVM load and APK/report/raw logs
belong in independent provenance JSON/artifacts, not this minimal Gradle envelope.
They remain required producer CI evidence, not arbitrary extra manifest keys or
consumer permission to infer runtime behavior. No counters/Ready/business claims
are in the packaging envelope. No source/hash signature/attestation is claimed.

Ownership after root freeze/activation:
- Checker owns new checks/verify_inputs.py, producer and negative controls; use the canonical docs schema rather than a divergent second shape. Runtime validation is stdlib-only and needs no schema package or network.
- UI owns Gradle-side paired properties and required invocation of the single checker-owned strict validator; do not separately parse untrusted raw JSON with a duplicate-key-losing parser. Both properties absent→ordinary build; exactly one/empty/relative/
  nonexistent/malformed/mismatch→error before packaging. UI adds only
  <validatedRoot>/jniLibs and uses pinned JNA@aar. Validate the actually resolved
  dependency before packaging, not a second staging JNA copy.
- Native owner owns Rust interface/config/build ID inputs; no independent manifest
  schema variant. Root owns final spec and all cross-owner field/version changes.
- Shared schema/example negative vectors should cover wrong independentSHA, old
  source, one-property-only, missing/extra ABI, wrongfixedpath/library/hash,
  config/binding mismatch, wrongAAR/JNI/version/protocol/minAPI, unknown/duplicate
  key and wrong scalar type. Require applicable specific failure, no falsePASS.

## Shared verifier CLI and Gradle data

Invoke as an argument vector, never shell interpolation:

`python3 experiments/redesign/android-rust-bridge-lab/checks/verify_inputs.py --input-root <absolute-root> --expected-source-sha <independent40SHA> --binding <fixed-committed-Android-binding> --android-config <fixed-global-Android-config> --jna-aar <actual-resolved-JNA-AAR>`

The verifier locates the canonical docs schema at the known repository-relative path, rejects duplicate/unknown keys and validates the identities/files described above. Nonzero is required build failure. Do not load Python or search for it in the ordinary no-input build. Optional native builds require Python3 as an explicit CI/local packaging tool; no dependency install occurs in this verifier.

Gradle BuildConfig.MUYON_BRIDGE_PROTOCOL is1. MUYON_BRIDGE_SOURCE_SHA is the independently supplied source SHA after successful input validation, or empty in the normal no-Rust-input build. Neither value is an authorization or measured runtime counter. The adapter still needs an actual compatible Rust call to become diagnostic-ready.
