#!/usr/bin/env bash
# Isolated presentation checks only. No provider/IPC/network requests.
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-kotlinc}
output_dir=$(mktemp -d /tmp/muyon-cards-checks.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT
"$compiler" -Werror -jvm-target 17 \
  "$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/cards/CardModels.kt" \
  "$repo_root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/CardProjectionChecks.kt" \
  -include-runtime -d "$output_dir/checks.jar"
java -jar "$output_dir/checks.jar"
