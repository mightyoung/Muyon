#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-kotlinc}
output_dir=$(mktemp -d /tmp/muyon-save-consumer.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT
"$compiler" -Werror -jvm-target 17 \
  "$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraft.kt" \
  "$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup/SetupDraftArchive.kt" \
  "$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/persistence/HostDraftSaveState.kt" \
  "$repo_root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/HostDraftSaveStateChecks.kt" \
  -include-runtime -d "$output_dir/checks.jar"
java -jar "$output_dir/checks.jar"
