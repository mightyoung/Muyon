#!/usr/bin/env bash
set -eu
src=$(cd "$(dirname "$0")" && pwd)
compiler=${RD_P04_KOTLINC:-/tmp/muyon-spike01-toolchain/kotlin-2.2.20/kotlinc/bin/kotlinc}
export JAVA_HOME=${RD_P04_JAVA_HOME:-/tmp/muyon-spike01-toolchain/jdk/jdk-17.0.20.1+1}
out=${RD_P04_OUTPUT:-/tmp/rd-p04-output}
mkdir -p "$out"
"$compiler" "$src/Presenter.kt" "$src/tests/PresenterTest.kt" -jvm-target 17 -include-runtime -d "$out/presenter-tests.jar"
"$JAVA_HOME/bin/java" -jar "$out/presenter-tests.jar"
