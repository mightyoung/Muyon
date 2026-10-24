#!/usr/bin/env bash
set -euo pipefail
repo_root=$(git rev-parse --show-toplevel)
compiler=${KOTLINC:-kotlinc}
json_jar=${JSON_JAR:?Set JSON_JAR to the actual org.json JVM artifact; no Android stubs}
output_dir=$(mktemp -d /tmp/muyon-host-projection.XXXXXX)
trap 'rm -rf "$output_dir"' EXIT
source_root="$repo_root/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/chat"
"$compiler" -Werror -jvm-target 17 -classpath "$json_jar" \
  "$source_root/ProductChatRuntime.kt" "$source_root/ProductSendGate.kt" \
  "$source_root/../development/DevelopmentController.kt" \
  "$source_root/ProductHttpsTransport.kt" \
  "$source_root/persistence/HostDraftSaveState.kt" \
  "$source_root/persistence/NativeLocalDraftCodec.kt" \
  "$source_root/persistence/HostLocalDraftSession.kt" \
  "$source_root/../agents/setup/BotSetupDraft.kt" \
  "$source_root/../agents/setup/SetupDraftArchive.kt" \
  "$repo_root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/HostContinuationChecks.kt" \
  "$repo_root/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/HostProjectionChecks.kt" \
  -include-runtime -d "$output_dir/checks.jar"
java -cp "$output_dir/checks.jar:$json_jar" com.mightyoung.muyon.product.chat.HostProjectionChecksKt
