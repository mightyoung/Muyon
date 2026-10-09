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
flutter test --no-pub --reporter expanded --timeout 120s test/responsive_shell_test.dart --plain-name "assistant_is_default_and_four_destinations_are_exact"
