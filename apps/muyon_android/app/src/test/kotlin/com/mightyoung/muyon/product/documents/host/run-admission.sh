#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
output=$(mktemp -d /tmp/muyon-reader-admission.XXXXXX)
trap 'rm -rf "$output"' EXIT
source="$root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/documents/host"
"${KOTLINC:-kotlinc}" -Werror -jvm-target 17 "$source/LocalWorkspaceReaderPrincipal.kt" "$source/ReaderAdmissionRegistry.kt" \
  "$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/ReaderAdmissionChecks.kt" "$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/ReaderBatchChecks.kt" -include-runtime -d "$output/checks.jar"
java -jar "$output/checks.jar"
