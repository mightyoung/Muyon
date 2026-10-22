#!/usr/bin/env bash
set -euo pipefail
repository=$(git rev-parse --show-toplevel)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
source_root="$repository/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/shell"
"${KOTLINC:-kotlinc}" -Werror -jvm-target 17 -classpath "${JSON_JAR:?Set JSON_JAR to actual org.json JVM artifact}" \
  "$source_root/ReadOnlySnapshot.kt" \
  "$repository/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/ReadOnlySnapshotChecks.kt" \
  -include-runtime -d "$output/checks.jar"
java -cp "$output/checks.jar:$JSON_JAR" com.mightyoung.muyon.product.ui.shell.ReadOnlySnapshotChecksKt
