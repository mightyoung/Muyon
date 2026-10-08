#!/usr/bin/env bash
# Full local gate: analyze every package and run every suite.
# Usage: scripts/verify.sh   (from any directory inside the repo)
# Exit 0 only when analysis is clean and the only test failures are listed
# in KNOWN_FAILURES. Prints one summary line per suite.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Empty: the former `screenshot_test.dart: desktop settings` allow-list entry
# was removed on 2026-10-05 by updating that golden baseline. See
# packages/inquiry_module/MIGRATION_VALIDATION.md.
KNOWN_FAILURES=()

# Local proxies break Flutter's localhost test websocket.
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY=localhost,127.0.0.1,::1

status=0
cd "$ROOT" && flutter pub get >/dev/null || { echo "pub get failed"; exit 1; }

for pkg in packages/muyon_module_api packages/muyon_ui packages/prototype_module packages/research_module packages/supplier_core packages/inquiry_module apps/muyon apps/muyon_ui_preview; do
  if out=$(cd "$ROOT/$pkg" && flutter analyze 2>&1); then
    echo "analyze  $pkg: ok"
  else
    echo "analyze  $pkg: FAILED"; echo "$out" | grep -E " • " ; status=1
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
  "ui_preview|apps/muyon_ui_preview|test"
  "inquiry|apps/muyon|../../packages/inquiry_module/test"   # needs host asset keys
)
for entry in "${suites[@]}"; do
  IFS='|' read -r name dir target <<<"$entry"
  log=$(cd "$ROOT/$dir" && flutter test --no-pub --timeout 120s "$target" 2>&1 | tr '\r' '\n')
  summary=$(echo "$log" | grep -E "All tests passed|Some tests failed|All other tests passed" | tail -1 | sed -E 's/^[0-9:]+ //')
  unexpected=$(echo "$log" | grep -E "\[E\]$" | sed -E 's/^[0-9:]+ [+~0-9 -]+: //; s/ \[E\]$//' | sort -u | while read -r failure; do
    known=0
    # bash 3.2 (macOS) treats an empty array as unbound under set -u.
    for k in ${KNOWN_FAILURES[@]+"${KNOWN_FAILURES[@]}"}; do [[ "$failure" == *"$k"* ]] && known=1; done
    [[ $known -eq 0 ]] && echo "$failure"
  done)
  if [[ -z "$summary" ]]; then
    echo "test     $name: NO SUMMARY (crashed or hung)"; status=1
  elif [[ -n "$unexpected" ]]; then
    echo "test     $name: FAILED  $summary"; echo "$unexpected" | sed 's/^/           /'; status=1
  else
    echo "test     $name: ok  $summary"
  fi
done

exit $status
