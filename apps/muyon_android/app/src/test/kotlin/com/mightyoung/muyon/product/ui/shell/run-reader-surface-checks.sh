#!/usr/bin/env bash
set -euo pipefail
repository=$(git rev-parse --show-toplevel)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
source_root="$repository/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product"
"${KOTLINC:-kotlinc}" -Werror -jvm-target 17 \
 "$source_root/ui/documents/DocumentReaderModels.kt" "$source_root/ui/shell/ReaderSurfaceFence.kt" \
 "$repository/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/ReaderSurfaceFenceChecks.kt" \
 -include-runtime -d "$output/checks.jar"
java -jar "$output/checks.jar"
