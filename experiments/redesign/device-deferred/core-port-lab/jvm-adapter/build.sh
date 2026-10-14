#!/usr/bin/env bash
set -eu
src=$(cd "$(dirname "$0")" && pwd)
compiler=${RD_P05_KOTLINC:-/tmp/muyon-spike01-toolchain/kotlin-2.2.20/kotlinc/bin/kotlinc}
export JAVA_HOME=${RD_P05_JAVA_HOME:-/tmp/muyon-spike01-toolchain/jdk/jdk-17.0.20.1+1}
out=${RD_P05_OUTPUT:-/tmp/rd-p05-jvm-output}
mkdir -p "$out"
"$compiler" "$src/Json.kt" "$src/Port.kt" "$src/Presentation.kt" "$src/Driver.kt" -jvm-target 17 -include-runtime -d "$out/rd-p05-driver.jar"
