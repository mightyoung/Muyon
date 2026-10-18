# Shipping Service JVM evidence, 2026-10-18

Product source: `2fbdc13efd84cabf04623775f87e762cd0d08c11`. All product runs below used that exact clean HEAD, before adding these verification-only files. Product runtime, frozen RED assertions, `checks/`, and workflows were not changed.

## Fresh results

| Actual execution | Result | Evidence under `/workspace/leaderb-evidence-20261018/a/` |
| --- | --- | --- |
| Existing `linux_gate.py --mode full` | GREEN, exit0: Rust unit3/integration6/doc0, shipping JVM5, missing-library1, separate panic recovery1 | `linux/verdict.json`, stage logs and sidecar command records |
| New shipping JVM probe | Exit0, all four built-in variants; actual library mapping, Ready/admission/Completed, original task/receipt identity, epoch/lease/visibility rejection, request dedup/conflict, lookup byte preservation, close/join slot retention, fresh-epoch restore | `service-verification/baseline.log`, `baseline/runs.tsv`, original private directories |
| Private durable oracle on the **same JVM runs** | Exit0, four variants; original native receipt/raw source, durable IDs, task calls/steps2, one indexed run, final exact safe projection/receipt reference, no raw canary in final outbound | `service-verification/durable-oracle.log` |
| New durable oracle controls | TDD: empty checker fails five semantic negative controls; implemented checker passes original sibling plus five negatives, 6/6 | `records-red.log`, `records-green.log`, `records-portable-green.log` under `service-verification/` |
| Existing Service Rust targets | Exit0, 13 tests: controller4/lifecycle4/oracle1/root2/runtime2, default concurrency | `service-private/run.log` |
| Existing pure JVM state checks | Exit0, groups 16+22+29+68+12+16 =163; labels independently retained | `state-runner.log` |
| Existing arm64 producer, first attempt | INVALID setup, sdkmanager network failure | `arm64-v8a/`, `arm64-runner.log` |
| Existing arm64 producer, proxy diagnosis applied | INVALID setup: official NDK license not accepted, no source.properties | `arm64-v8a-proxy/`, `arm64-proxy-runner.log` |
| Existing x86_64 producer | INVALID setup: same unaccepted NDK license | `x86_64/`, `x86-runner.log` |
| Existing package producer | INVALID setup/input stage: no same-source ABI artifacts; SDK packages were skipped because licenses were not accepted | `package/`, `package-runner.log` |

NDK cross-link, Rust/JNA ELF/import checks, six APK native entries, APK/16KiB zip alignment, zipalign, lint/AIDL compilation, and ordinary no-native Compose assembly remain **NOT_RUN**. INVALID setup is not semantic RED. No new licenses were accepted and no SDK package installation was bypassed. Existing environment proxy and system trust store were supplied to sdkmanager after its initial network failure; TLS verification remained enabled.

The Rust private `ServiceEvidenceObserver` independently observes four **separate** runs: handler1/receipt1/payload2, first-tools1/final-tools0, expected mapping and no raw canary. It does not correlate its task IDs or captured first payload to the actual JVM runs. The JVM durable oracle observes the last persisted outbound only. It cannot prove the JVM run's exact handler count or first actual payload. The existing private oracle uses semantic payload assertions, not full byte golden equality of both payloads. Those coverage boundaries remain open for final acceptance.

Android ART/Binder/PID/UID/permissions/fsync/kill/rebind/device/emulator runtime remains **NOT_RUN**. Linux filesystem operations or fresh-epoch controller reopen are not Android platform lifecycle tests.

## Immutable artifacts

| Artifact | SHA256 |
| --- | --- |
| Default shipping Linux library | `15d520efc06323709e2bbdcb6b8bf82bf214ac90520b5c936cc0ca8b4ebac8c1` |
| Fresh JVM binding | `94b4dc43effd3d47b1fe2ada522c6d418e32ad3b671a72581c4d4591264eb6e7` |
| Fresh Android binding (byte-equal to committed binding) | `6fec4795a50cab1b629cb19c45562fb435a805f542bc2312da100995aa5636db` |
| ShippingServiceProbe.kt | `fd89033de3630a2805b419fd5f420e303912af2df467c9073a2bc3f7d3a11db2` |
| Compiled probe.jar | `d65fba134461a44be8d35652cf8c12d346deb8c129e1373415eadc4165afcfb9` |

Default shipping features are empty; bindgen and panic targets are separate. `a/fixed-product-inputs.json` freezes product file hashes while HEAD was clean; `a/service-verification/provenance.json` records artifact hashes and scope. `a/toolchain/provenance.json` records official tool URLs and verified checksums. Tools: Rust1.99.0, Temurin17.0.20.1+1, Kotlin2.2.20, JNA5.19.1; SDK manager19.0 downloaded from official Google metadata. No binaries or machine raw logs are committed.

## Reproduction

Use a separate clean checkout of the product SHA to run the unchanged producers. Do not change HEAD or dirty that checkout until they finish. Keep all targets/evidence outside the source tree.

1. Run existing `checks/linux_gate.py --mode full --evidence-dir "$E/linux" --work-dir "$W/linux"` with pinned Rust/JDK17. It builds the default library, independently generates JVM and Android bindings, compiles/runs the old JVM cases, and preserves a separate panic library.
2. Compile this probe with the fresh **JVM** binding and pinned JNA:

```sh
bash "$KOTLIN/bin/kotlinc" \
  "$E/linux/jvm/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt" \
  "$V/ShippingServiceProbe.kt" -jvm-target 17 -classpath "$JNA" \
  -include-runtime -d "$E/probe.jar"
mkdir -p "$E/service-baseline"
"$JAVA_HOME/bin/java" -cp "$E/probe.jar:$JNA" \
  muyon.shippingverification.ShippingServiceProbe \
  2fbdc13efd84cabf04623775f87e762cd0d08c11 \
  "$E/linux/shipping/libmuyon_android_contract_bridge.so" "$E/service-baseline"
python3 -B "$V/verify_shipping_records.py" \
  --runs "$E/service-baseline/runs.tsv" \
  --source 2fbdc13efd84cabf04623775f87e762cd0d08c11
MUYON_SERVICE_BASELINE="$E/service-baseline" python3 -B -m unittest \
  discover -s "$V" -p test_verify_shipping_records.py
```

`V` is this verification directory; `E`, `W`, `KOTLIN`, `JNA`, and `JAVA_HOME` are absolute caller-supplied paths. An absent tool/native library/record is an execution failure, never an accepted skip. Each baseline needs a new work directory.

3. Existing private Rust evidence command (separate target):

```sh
cargo test --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml \
  --offline --locked --release --test service_oracle --test service_runtime \
  --test service_lifecycle --test service_controller --test service_root
```

## Source guard inverses

The probe freezes exact assertion names before source mutation: `SERVICE_SHIPPING_ASSERT:duplicate_is_existing`, `SERVICE_SHIPPING_ASSERT:stale_epoch_rejected`, and `SERVICE_SHIPPING_ASSERT:slot_held_until_join`. Main coordinator owns the separate source copies, compiled mutants, strict verdicts and final integration. This report does not preclaim those inverses KILLED. Oracle record corruptions validate this verifier only; they do not substitute for compiled product inverses.
