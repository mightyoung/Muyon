#!/usr/bin/env bash
set -euo pipefail
# Reuse preinstalled tools; no downloads, Android dependencies or repository outputs.
RD_P08_ANDROID_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
RD_P08_KOTLINC="${RD_P08_KOTLINC:-/tmp/muyon-spike01-toolchain/kotlin-2.2.20/kotlinc/bin/kotlinc}"
RD_P08_JAVA="${RD_P08_JAVA:-/tmp/muyon-spike01-toolchain/jdk/jdk-17.0.20.1+1/bin/java}"
RD_P08_JVM_OUT="$(mktemp -d /tmp/rd-p08-android-jvm.XXXXXX)"
printf 'JVM artifact directory: %s\n' "$RD_P08_JVM_OUT"
"$RD_P08_KOTLINC" "$RD_P08_ANDROID_DIR/SupplierScreenModel.kt" "$RD_P08_ANDROID_DIR/ProjectionTest.kt" -include-runtime -d "$RD_P08_JVM_OUT/projection-tests.jar"
"$RD_P08_JAVA" -jar "$RD_P08_JVM_OUT/projection-tests.jar"
"$RD_P08_KOTLINC" "$RD_P08_ANDROID_DIR/SupplierScreenModel.kt" "$RD_P08_ANDROID_DIR/RecoveryProbe.kt" -include-runtime -d "$RD_P08_JVM_OUT/recovery-probes.jar"
"$RD_P08_JAVA" -jar "$RD_P08_JVM_OUT/recovery-probes.jar"
