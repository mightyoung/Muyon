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
