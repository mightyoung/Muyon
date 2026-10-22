#!/usr/bin/env bash
# Only the new pure Kotlin config/ordinary-Send/projection checks, no aggregates.
set -euo pipefail
lab_dir=$(cd "$(dirname "$0")" && pwd)
compiler=${MUYON_UI_KOTLINC:-kotlinc}
output=${MUYON_UI_OUTPUT:-/tmp/muyon-search-state-checks}
mkdir -p "$output"
sources="$lab_dir/state/src/main/kotlin/com/mightyoung/muyon/androidlab"
"$compiler" "$sources/ChatReadContract.kt" "$sources/FrontendChatPolicy.kt" "$sources/SearchSettings.kt" "$lab_dir/state/src/searchTest/kotlin/com/mightyoung/muyon/androidlab/SearchChecks.kt" -jvm-target 17 -include-runtime -d "$output/search-checks.jar"
java -jar "$output/search-checks.jar"
