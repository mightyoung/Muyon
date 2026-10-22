#!/usr/bin/env bash
set -euo pipefail
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
root=/workspace/muyon-ui-candidate/apps/muyon_android/app/src
/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 "$root/main/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraft.kt" \
 "$root/main/kotlin/com/mightyoung/muyon/product/agents/setup/SetupDraftArchive.kt" \
 "$root/main/kotlin/com/mightyoung/muyon/product/ui/configuration/BotConfigurationEditor.kt" \
 "$root/test/kotlin/com/mightyoung/muyon/product/ui/configuration/ConfigurationChecks.kt" \
 -include-runtime -d "$out/checks.jar"
/workspace/ui-shell-tools/jdk-17.0.21+9/bin/java -jar "$out/checks.jar"
