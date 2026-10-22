#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-kotlinc}
json_jar=${JSON_JAR:?Use the actual org.json artifact}
output_dir=$(mktemp -d /tmp/muyon-draft-store-checks.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT
"$compiler" -Werror -jvm-target 17 -classpath "$json_jar" \
  "$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat/persistence/HostDraftStore.kt" \
  "$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup/BotSetupDraft.kt" \
  "$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup/SetupDraftArchive.kt" \
  "$repo_root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/persistence/HostDraftStoreChecks.kt" \
  -include-runtime -d "$output_dir/checks.jar"
java -cp "$output_dir/checks.jar:$json_jar" com.mightyoung.muyon.product.chat.persistence.HostDraftStoreChecksKt
