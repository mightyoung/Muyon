# Independent API26 packaging probe

This Gradle root builds the OCR adapter as a standard Android AAR and a minimal
APK that consumes its transitive pinned OpenCV/ORT AARs. It has no Activity,
Service, IPC entry point, permissions or production App connection. Both modules
set minSdk26. The main application and shared CI are outside this build.

Use JDK17, Gradle8.13, AGP8.11.1, SDK36 revision2 and Build Tools36.0.0. Configure
`ANDROID_HOME` and `ANDROID_USER_HOME` to writable, already licensed installations.
No task here accepts SDK licenses. The known prior SDK license restored in this
execution is documented in `../evidence/native-toolchain.json`.

```sh
OCR_ASSETS=/external/ocr-assets gradle --no-daemon :adapter:assembleDebug :probe:assembleDebug
python ../checks/native_packaging_audit.py /external/aar-inputs \
  --apk probe/build/outputs/apk/debug/probe-debug.apk \
  --adapter-aar adapter/build/outputs/aar/adapter-debug.aar \
  --ndk "$ANDROID_HOME/ndk/28.2.13676358" --require-static-pass
"$ANDROID_HOME/build-tools/36.0.0/zipalign" -c -P 16 -v 4 \
  probe/build/outputs/apk/debug/probe-debug.apk
```

The external asset cache is verified against models.lock.json before staging.
Only tiny det ONNX, rec ONNX and rec YAML are packaged at the exact paths expected
by OfficialOcrAdapter. No weights, SDK, AAR, APK or signing key belong in Git.
OpenCV is official `org.opencv:opencv:4.12.0`, source release tag 4.12.0
(commit `49486f61fb25722cbcf586b7f4320921d46fb38e`). Maven hashes and individual
native hashes are recorded by the audit. Native libraries are retained byte for
byte with `keepDebugSymbols`, avoiding an unrecorded stripping transformation.

The standard adapter AAR contains adapter classes and assets; consumer Gradle
resolves ORT/OpenCV as transitive dependencies. It is not a fat AAR. The probe APK
includes all four published ABIs and exactly 16 native libraries. Only the two
64-bit ABIs satisfy the 16KiB ELF gate; the published 32-bit libraries remain
4KiB. The APK stores every native library uncompressed at 16KiB ZIP boundaries.
The checker validates LOAD congruence and RELRO write overlap, strong dynamic
imports (including symbol versions) against actual API26 NDK stubs, native entry
completeness, unchanged native bytes and all three model/config assets.

These are build and static compatibility results. API26 ART/JNI load, 16KiB
loading, Android det/rec output equivalence, memory and host libc++ coexistence
are NOT_RUN until tested on an authorized device/emulator and integrated host.
Run `native_packaging_negative.py` against the resulting APK to reproduce checker
negative controls for alignment, missing native files, corrupt assets and missing
API26 import providers.
