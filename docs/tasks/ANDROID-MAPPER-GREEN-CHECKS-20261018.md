# Strict mapper6 GREEN runner — resumed 2026-10-18

Product source is fixed at `aa0bc2cf9527911c8764b8578ee706f3499fe82f` (b1 plus native f60). All12 Kotlin input blobs/SHA256s and the original6 fixture names match b1 exactly. This is a checks-only runner; it does not change generated bindings, fixtures, product source, or original RED descriptors/classifiers.

Run from an environment with official JDK17 on PATH/JAVA_HOME, Kotlin2.2.20 and pinned JNA5.14.0 (`4fb141dd8ef6b0585ffceea4bc49602fbc6312fa977e2c488794ea3e6aafecae`). Use a new evidence directory:

```sh
python3 -B /path/to/checks/mapper_control_green.py \
  --source-root /path/to/exact-aa0-checkout \
  --library /path/to/shipping/libmuyon_android_contract_bridge.so \
  --bindgen /path/to/uniffi-bindgen \
  --kotlinc /path/to/kotlin-2.2.20/bin/kotlinc \
  --jna /path/to/jna-5.14.0.jar \
  --evidence-dir /tmp/new-mapper-evidence
```

The runner checks exact source HEAD and Kotlin source hashes, runs fresh JVM-profile generation from the shipping library, rejects panic-feature bindings, compiles the original6 fixtures and probes, and verifies actual native handshake plus `/proc/self/maps` library mapping. Acceptance requires exit0 and exactly one source/library header, all6 named PASS lines in order, and the exact metadata-only summary. Extra output, missing/renamed/reordered cases, wrong source, failed loads, compiler failure, signals and timeouts are INVALID. Library bytes must remain unchanged. Native build identity is checked; keep separate actual shipping build provenance because the runner does not reconstruct the native build command.

Controls are synthetic classifier tests, not execution evidence. Resumed bridge checks68P/0F include mapper RED3 + GREEN3; logs and real Git source audit are in `/tmp/Muyon-checks-evidence/`. Actual mapper6 execution remains NOT_RUN by the checks owner; the mapper owner performs it separately. No Android ART/Binder/runtime or shipping/service acceptance is implied. The descriptor product-source commit differs from the checks runner commit by design; record both actual identities when collecting execution evidence.
