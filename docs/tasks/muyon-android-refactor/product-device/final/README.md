# Fixed candidate local evidence

Source candidate: 7b063cb4089fe21fdaf82657bcf00408e3f138b1.
Build ID: 7b063cb4089fe21fdaf82657bcf00408e3f138b1:e3e140e4584aff5a9bb8de35162e5fc42bb6e1318e96ec14d5c996c97013aaf0.

SUITE-MANIFEST.json binds the unchanged APKs, source identity, device, all 21
required methods and every captured run's log/build/APK hashes. SUITE.json is
the successful content/provenance check. The methods comprise one setup, 16
core behavior methods and four picker/private-attachment behavior methods.
All six adb runs exited zero and contain complete positive summaries. Original
logs equal the final captured command outputs byte for byte.

PACKAGE.json verifies both product native ABIs, bundled SQLite, generated bridge
bytes, native digest and ELF/APK alignment. Its build ID and APK digest match
the suite manifest. DEVICE.json records the observed API26 ARM64 emulator with
SELinux Enforcing; x86_64 has cross-build proof only.

RUST.log contains 127 passing executions, zero skipped. The product Rust tree
c0bcc4306721dc39f75062c078319ec87931f1fa and reused laboratory dependencies are
identical between the Rust test snapshot and this candidate; only Android test
helpers changed afterward. CLIPPY.log is the strict check; ANDROID-BUILD.log
includes actual APK/test compilation and lint. PYTHON-CHECKS.log records four
gate tests, including refusal of changed passing logs and mismatched identities.

The verification commands used were:

```sh
python3 apps/muyon_android/checks/suite_gate.py docs/tasks/muyon-android-refactor/product-device/final/SUITE-MANIFEST.json apps/muyon_android/app/src/androidTest/kotlin
python3 -m unittest discover -s apps/muyon_android/checks -p 'test_*.py'
```

APK paths and exact hashes are in the manifest. These are debug acceptance
artifacts, not a release. Verification scripts/evidence were sealed after the
product candidate; product, fixture and native source inputs remain unchanged.
Overall acceptance remains HOLD: I04 and real model/search/current-price proof
are not supplied by local fixture, packaging or instrumentation results. See
../../ACCEPTANCE-MATRIX.md for the remaining compound boundaries.
