#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
if ! command -v "${KOTLINC:-kotlinc}" >/dev/null 2>&1; then
  echo 'NOT_RUN: existing Kotlin compiler unavailable; no installation attempted.' >&2
  exit 2
fi
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
src="$root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/documents"
"${KOTLINC:-kotlinc}" -Werror -jvm-target 17 "$src/DocumentReaderModels.kt" "$src/OfficeTextPreview.kt" \
  "$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents/DocumentReaderChecks.kt" \
  -include-runtime -d "$out/checks.jar"
java -jar "$out/checks.jar"
