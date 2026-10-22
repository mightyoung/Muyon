#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
output=$(mktemp -d /tmp/muyon-reader-admission.XXXXXX)
trap 'rm -rf "$output"' EXIT
source="$root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/documents/host"
"${KOTLINC:-kotlinc}" -Werror -jvm-target 17 "$source/LocalWorkspaceReaderPrincipal.kt" "$source/ReaderAdmissionRegistry.kt" "$source/ReaderAdministrativeBatch.kt" "$source/ReaderPresentationDeadline.kt" "$source/ReaderContinuationController.kt" \
  "$root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/shell/ReaderSurfaceFence.kt" \
  "$root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/documents/DocumentReaderModels.kt" \
  "$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/ReaderAdmissionChecks.kt" "$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/ReaderBatchChecks.kt" "$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/ReaderContinuationChecks.kt" "$root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/documents/host/ReaderControllerChecks.kt" -include-runtime -d "$output/checks.jar"
java -jar "$output/checks.jar"
