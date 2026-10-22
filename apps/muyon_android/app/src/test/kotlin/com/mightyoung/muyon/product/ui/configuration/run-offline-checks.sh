#!/usr/bin/env bash
set -euo pipefail
repository=$(git rev-parse --show-toplevel)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
source_root="$repository/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product"
"${KOTLINC:-kotlinc}" "$source_root/agents/setup/BotSetupDraft.kt" \
  "$source_root/ui/configuration/BotConfigurationEditor.kt" \
  "$repository/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/configuration/ConfigurationChecks.kt" \
  -include-runtime -d "$output/checks.jar"
java -jar "$output/checks.jar"
