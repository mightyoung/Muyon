# Batch 4 same-source Android verification

These are verification-only runners. They preserve the stock gates and their historical exact2f contracts. No runtime/gate/timing source is changed. Run against a clean, frozen candidate; all evidence and targets must be outside its source tree.

```
source /workspace/batch4/tools/android/env.sh
python3 -B docs/tasks/leaderb-batch4-android-validation-20261018/run-suite.py "$PWD" /workspace/batch4/evidence/android/final
```

The suite builds API24 arm64-v8a and x86_64 native producers, Linux/JVM/JNI with panic and missing-library controls, shipping Service four variants with same-run durable oracle and seven record controls, three compiled shipping Service semantic inverses, five separate private Rust Service targets, packaging/lint/AIDL/APK/zipalign, ordinary no-native-input assembly, and existing checker controls. It records each stage's exit code. A failed stage remains a failure; subsequent independent stages may still run. No generated outcome is committed here, so this verification source can be part of the exact candidate SHA being tested.

The Service inverse contract must match actual candidate HEAD and clean status, fresh Linux/service GREEN manifests, exact source input hashes, same-run library/jar/binding hashes and the frozen probe source. Baselines check the real mapped library and build identity. Each inverse requires its exact assertion and exit1 with no timeout/forced cleanup, and its paired four-variant baseline must exit0. Arbitrary caller hashes alone are insufficient. The same-run contract is generated only after the fresh producers, and an absent verdict/artifact causes failure.

The frozen probe and durable record verifier are copied byte-for-byte from Batch3 retained verification source. Its source is the fixed `a0c14e13` verification lineage documented by Batch3; the product build identity comes from current HEAD, never the old product2f. `test_same_source_contract.py` checks cross-source/library/probe/INVALID/changed-input rejection and exact inverse classifier behavior.

Ordinary assembly follows packaging only after copies of same-run diagnostic APKs are retained. JVM/private Rust runs are independent evidence. They do not establish Android ART, Binder, UID/permissions, Android fsync, kill/rebind, device or emulator behavior. The same JVM durable oracle cannot establish its first actual payload or exact handler count. No live provider, credentials, paid service, deployment, publication, CI dispatch or Claude review is used.

Tools are independently restored from official sources. Only the authorized selected-package `android-sdk-license` hash `24333f8a63b6825ea9c5514f83c2829b004d1fee` may be installed; sdkmanager runs with stdin disabled and never blanket `--licenses`. Setup/download/license/skill reports remain external evidence. Official Android skills are pinned to `5bda39f154fb859a08d45e2392f3568e049f83fb`: 412 complete repository files were source-verified; 402 belong to the 30 installed skill subtrees; 10 are repository metadata/readme files. Only relevant `android-cli` was loaded.
