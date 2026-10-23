#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-kotlinc}
json_jar=${JSON_JAR:?Set JSON_JAR to the actual org.json JVM artifact}
output_dir=$(mktemp -d /tmp/muyon-development-controller.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT
source_root="$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product"
"$compiler" -Werror -jvm-target 17 -classpath "$json_jar" \
  "$source_root/chat/ProductChatRuntime.kt" "$source_root/chat/ProductSendGate.kt" \
  "$source_root/chat/ProductHttpsTransport.kt" "$source_root/development/DevelopmentController.kt" \
  "$source_root/chat/persistence/HostDraftSaveState.kt" \
  "$source_root/chat/persistence/NativeLocalDraftCodec.kt" \
  "$source_root/chat/persistence/HostLocalDraftSession.kt" \
  "$source_root/agents/setup/BotSetupDraft.kt" "$source_root/agents/setup/SetupDraftArchive.kt" \
  "$repo_root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/development/DevelopmentControllerChecks.kt" \
  -include-runtime -d "$output_dir/checks.jar"
java -cp "$output_dir/checks.jar:$json_jar" com.mightyoung.muyon.product.chat.DevelopmentControllerChecksKt
