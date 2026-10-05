#!/usr/bin/env bash
# Automatic CI gate (Linux, headless): analyze every package and run every suite.
# Usage: scripts/ci.sh   (from any directory inside the repo)
# Exit 0 only when pub get, every analyze and every suite succeed.
#
# How this differs from scripts/verify.sh, and why:
#  1. Excludes tests tagged `screenshot` (flutter test --exclude-tags
#     screenshot). Those three files in packages/inquiry_module/test
#     (screenshot_test, ontology_screenshot_test, generated_icon_sources_test)
#     render with macOS system fonts and compare against macOS-rendered golden
#     PNGs, so on Linux they would differ. They stay covered by the manual
#     macOS `verify` workflow / scripts/verify.sh. No other test is excluded.
#  2. No KNOWN_FAILURES allow-list: any failed test fails the gate. Suites are
#     judged by flutter's exit code (not by grepping the summary), and a
#     crashed or hung suite also fails.
#  3. Keeps going after a failure so one run reports every broken step, then
#     exits non-zero at the end. Prints a final CI SUMMARY line.
#  4. Prints failing test output in full (the workflow uploads the whole log as
#     an artifact), instead of only one summary line per suite.
#  5. Does not depend on macOS bash 3.2 quirks (no empty-array workarounds).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Proxies are cleared only after pub get (pub get needs them to reach pub.dev);
# they break Flutter's localhost test websocket.
EXCLUDE_TAGS="screenshot"

status=0
cd "$ROOT" || exit 1
flutter pub get >/dev/null || { echo "pub get failed"; echo "CI SUMMARY: FAILED (pub get)"; exit 1; }

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY=localhost,127.0.0.1,::1

failed=()

for pkg in packages/muyon_module_api packages/muyon_ui packages/prototype_module packages/research_module packages/supplier_core packages/inquiry_module apps/muyon; do
  if out=$(cd "$ROOT/$pkg" && flutter analyze 2>&1); then
    echo "analyze  $pkg: ok"
  else
    echo "analyze  $pkg: FAILED"; echo "$out"
    status=1; failed+=("analyze:$pkg")
  fi
done

# suite name | working dir | test target
suites=(
  "module_api|packages/muyon_module_api|test"
  "muyon_ui|packages/muyon_ui|test"
  "prototype|packages/prototype_module|test"
  "research|packages/research_module|test"
  "supplier_core|packages/supplier_core|test"
  "host|apps/muyon|test"
  "inquiry|apps/muyon|../../packages/inquiry_module/test"   # needs host asset keys
)
for entry in "${suites[@]}"; do
  IFS='|' read -r name dir target <<<"$entry"
  log=$(cd "$ROOT/$dir" && flutter test --no-pub --timeout 120s --exclude-tags "$EXCLUDE_TAGS" "$target" 2>&1; echo "exit=$?")
  code=${log##*exit=}
  log=$(echo "$log" | tr '\r' '\n')
  summary=$(echo "$log" | grep -E "All tests passed|Some tests failed|All other tests passed" | tail -1 | sed -E 's/^[0-9:]+ //')
  if [[ "$code" -eq 0 && -n "$summary" ]]; then
    echo "test     $name: ok  $summary"
  else
    echo "test     $name: FAILED (exit $code)  ${summary:-NO SUMMARY (crashed or hung)}"
    echo "$log" | grep -E "\[E\]$|Expected:|Actual:|EXCEPTION|Error:" | sed 's/^/           /'
    status=1; failed+=("test:$name")
  fi
done

if [[ $status -eq 0 ]]; then
  echo "CI SUMMARY: OK (analyze 7/7, test 7/7 suites, excluded tags: $EXCLUDE_TAGS)"
else
  echo "CI SUMMARY: FAILED (${failed[*]})"
fi
exit $status
