#!/usr/bin/env bash
set -euo pipefail
lab_dir=$(cd "$(dirname "$0")" && pwd)
compiler=${MUYON_UI_KOTLINC:-kotlinc}
java_bin=${MUYON_UI_JAVA:-java}
output=${MUYON_UI_OUTPUT:-/tmp/muyon-android-compose-state-checks}
mkdir -p "$output"
"$compiler" "$lab_dir"/state/src/main/kotlin/com/mightyoung/muyon/androidlab/*.kt \
  "$lab_dir"/state/src/test/kotlin/com/mightyoung/muyon/androidlab/*.kt \
  -jvm-target 17 -include-runtime -d "$output/state-checks.jar"
"$java_bin" -jar "$output/state-checks.jar"
