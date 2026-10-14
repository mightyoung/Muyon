#!/usr/bin/env bash
set -eu
src=$(cd "$(dirname "$0")" && pwd)
compiler=${RD_P05_KOTLINC:-/tmp/muyon-spike01-toolchain/kotlin-2.2.20/kotlinc/bin/kotlinc}
export JAVA_HOME=${RD_P05_JAVA_HOME:-/tmp/muyon-spike01-toolchain/jdk/jdk-17.0.20.1+1}
out=${RD_P05_OUTPUT:-/tmp/rd-p05-jvm-output}
mkdir -p "$out"
export RD_P05_OUTPUT="$out"
"$compiler" "$src/Json.kt" "$src/CodecTest.kt" -jvm-target 17 -include-runtime -d "$out/codec-tests.jar"
"$JAVA_HOME/bin/java" -jar "$out/codec-tests.jar"
"$compiler" "$src/Json.kt" "$src/Port.kt" "$src/Presentation.kt" "$src/PresentationTest.kt" -jvm-target 17 -include-runtime -d "$out/presentation-tests.jar"
"$JAVA_HOME/bin/java" -jar "$out/presentation-tests.jar"
if [ ! -x /tmp/rd-p05-core-target/debug/rd-p05-core ]; then
  printf 'NOT_RUN actual Rust process tests: trusted binary unavailable\n'
  exit 2
fi
"$compiler" "$src/Json.kt" "$src/Port.kt" "$src/Presentation.kt" "$src/Controller.kt" "$src/ActualTest.kt" -jvm-target 17 -include-runtime -d "$out/actual-tests.jar"
"$JAVA_HOME/bin/java" -jar "$out/actual-tests.jar" "$src/../fixtures"
"$compiler" "$src/Json.kt" "$src/Port.kt" "$src/Presentation.kt" "$src/ValidationTest.kt" -jvm-target 17 -include-runtime -d "$out/validation-tests.jar"
"$JAVA_HOME/bin/java" -jar "$out/validation-tests.jar"
