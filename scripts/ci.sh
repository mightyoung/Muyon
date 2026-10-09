#!/usr/bin/env bash
# Temporary evidence runner only. NEVER MERGE. Product CI remains unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY=localhost,127.0.0.1,::1
cd apps/muyon
flutter analyze --no-pub
timeout 120s flutter test --no-pub --reporter expanded --timeout 60s test/ui_planning_harness_test.dart --plain-name "planning deadline commits cancellation before return"
timeout 240s flutter test --no-pub --reporter expanded --timeout 60s test/conversation_shell_return_test.dart

status=0
for file in responsive_shell_test conversation_shell_navigation_test conversation_workspace_pane_test conversation_shell_accessibility_test conversation_shell_recovery_test dynamic_object_navigation_test ui_workspace_store_test assistant_subconversation_widget_test; do
  echo "EVIDENCE FILE: $file"
  timeout 90s flutter test --no-pub --reporter expanded --timeout 60s "test/$file.dart" || status=1
done
for case in 'widget_test|default host opens platform and all four navigation sections' 'inquiry_plugin_test|platform opens the complete Folio module with one MaterialApp' 'module_lifecycle_regression_test|opening a declared v2 section must activate its module' 'inquiry_import_pipeline_test|task_center_menu_opens_production_file_context' 'prototype_wiring_test|shell data destination opens the prototype module'; do
  IFS='|' read -r file name <<< "$case"
  echo "EVIDENCE LEGACY: $file / $name"
  timeout 90s flutter test --no-pub --reporter expanded --timeout 60s "test/$file.dart" --plain-name "$name" || status=1
done
exit "$status"
