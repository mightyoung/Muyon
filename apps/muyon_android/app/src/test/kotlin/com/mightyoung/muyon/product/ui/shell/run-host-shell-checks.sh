#!/usr/bin/env bash
set -euo pipefail
repository=$(git rev-parse --show-toplevel)
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
source_root="$repository/apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product"
tests="$repository/apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell"
"${KOTLINC:-kotlinc}" -Werror -jvm-target 17 -classpath "${JSON_JAR:?Set JSON_JAR to actual org.json JVM artifact}" \
  "$source_root/chat/ProductChatRuntime.kt" "$source_root/chat/ProductSendGate.kt" "$source_root/chat/ProductHttpsTransport.kt" \
  "$source_root/development/DevelopmentController.kt" \
  "$source_root/agents/setup/BotSetupDraft.kt" "$source_root/agents/setup/SetupDraftArchive.kt" \
  "$source_root/chat/persistence/HostDraftSaveState.kt" "$source_root/chat/persistence/NativeLocalDraftCodec.kt" \
  "$source_root/chat/persistence/HostLocalDraftSession.kt" "$source_root/ui/shell/HostSetupController.kt" "$source_root/ui/shell/HostDraftPersistence.kt" \
  "$source_root/ui/shell/ReadOnlySnapshot.kt" "$source_root/ui/shell/RequestCandidates.kt" \
  "$tests/HostPersistenceProjectionChecks.kt" "$tests/HostSetupControllerChecks.kt" "$tests/RequestCandidateChecks.kt" -include-runtime -d "$output/checks.jar"
java -cp "$output/checks.jar:$JSON_JAR" com.mightyoung.muyon.product.ui.shell.HostSetupControllerChecksKt
java -cp "$output/checks.jar:$JSON_JAR" com.mightyoung.muyon.product.ui.shell.RequestCandidateChecksKt

java -cp "$output/checks.jar:$JSON_JAR" com.mightyoung.muyon.product.ui.shell.HostPersistenceProjectionChecksKt
