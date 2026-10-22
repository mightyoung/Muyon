#!/usr/bin/env bash
set -euo pipefail
repository=$(git rev-parse --show-toplevel)
output=$(mktemp -d "${TMPDIR:-/tmp}/muyon-setup-checks.XXXXXXXX")
trap 'rm -rf "$output"' EXIT
"${KOTLINC:-kotlinc}" \
  "$repository/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraft.kt" \
  "$repository/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraftChecks.kt" \
  -include-runtime -d "$output/checks.jar"
java -jar "$output/checks.jar"
