#!/usr/bin/env bash
# Automatic CI gate (Linux, headless): analyze every package and run every suite.
# Usage: scripts/ci.sh   (from any directory inside the repo)
# Exit 0 only when pub get, every analyze and every suite succeed.
#
# How this differs from scripts/verify.sh, and why:
#  1. No test exclusions and no tag filter: the golden tests that need macOS
#     system fonts (screenshot_test.dart, ontology_screenshot_test.dart in
#     packages/inquiry_module/test) skip themselves on Linux via
#     `skip: !hasFont` — the log shows roughly ~47 skips — and
#     generated_icon_sources_test.dart uses bundled fonts, so it passes on
#     Linux. They all stay covered by the manual macOS `verify` workflow /
#     scripts/verify.sh.
#  2. No KNOWN_FAILURES allow-list: any failed test fails the gate. Suites are
#     judged by flutter's exit code (not by grepping the summary), and a
#     crashed or hung suite also fails.
#  3. Keeps going after a failure so one run reports every broken step, then
#     exits non-zero at the end. Prints a final CI SUMMARY line.
#  4. Prints a failing suite's output (everything but the progress lines of
#     passing tests; the workflow also uploads the whole log as an artifact),
#     instead of only one summary line per suite.
#  5. Forces `--reporter compact`: on GitHub Actions flutter switches to its
#     `github` reporter, which has no "All tests passed!" line to check.
#  6. Does not depend on macOS bash 3.2 quirks (no empty-array workarounds).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

COVERAGE_DIR="$ROOT/.coverage-run"
mkdir -p "$COVERAGE_DIR"
rm -f "$COVERAGE_DIR/summary.json"
printf '[]\n' > "$COVERAGE_DIR/suite-summary.json"
status=0
cd "$ROOT" || exit 1
flutter pub get >/dev/null || { echo "pub get failed"; echo "CI SUMMARY: FAILED (pub get)"; exit 1; }

# Proxies are cleared only after pub get (pub get needs them to reach pub.dev);
# they break Flutter's localhost test websocket.
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY=localhost,127.0.0.1,::1

failed=()
analyze_ok=0
analyze_total=0

for pkg in packages/muyon_module_api packages/muyon_ui packages/prototype_module packages/research_module packages/supplier_core packages/inquiry_module apps/muyon apps/muyon_ui_preview; do
  analyze_total=$((analyze_total + 1))
  if out=$(cd "$ROOT/$pkg" && flutter analyze --no-pub 2>&1); then
    echo "analyze  $pkg: ok"
    analyze_ok=$((analyze_ok + 1))
  else
    echo "analyze  $pkg: FAILED"; echo "$out"
    status=1; failed+=("analyze:$pkg")
  fi
done

# Offline regressions for the local and CI gate exit-status contracts.
if gate_log=$(python3 "$ROOT/scripts/test_verification_gates.py" 2>&1); then
  echo "gate     test_verification_gates: ok"
else
  echo "gate     test_verification_gates: FAILED"
  printf '%s\n' "$gate_log"
  status=1; failed+=("gate:test_verification_gates")
fi

# scripts/test_doctor.sh: doctor scenario tests with fake tools, no network.
doctor_log=$(bash "$ROOT/scripts/test_doctor.sh" 2>&1; echo "exit=$?")
doctor_code=${doctor_log##*exit=}
doctor_summary=$(printf '%s\n' "$doctor_log" | grep -E '^all [0-9]+ scenarios passed$|^[0-9]+ passed, [0-9]+ failed$' | tail -1)
if [[ "$doctor_code" -eq 0 && -n "$doctor_summary" ]]; then
  echo "doctor   test_doctor: ok  $doctor_summary"
else
  echo "doctor   test_doctor: FAILED (exit $doctor_code)  ${doctor_summary:-NO SUMMARY (crashed or hung)}"
  printf '%s\n' "$doctor_log" | sed '$d' | sed 's/^/           /'
  status=1; failed+=("doctor:test_doctor")
fi

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
test_ok=0
test_total=0
for entry in "${suites[@]}"; do
  test_total=$((test_total + 1))
  IFS='|' read -r name dir target <<<"$entry"
  mkdir -p "$COVERAGE_DIR/$name"
  rm -f "$COVERAGE_DIR/$name/lcov.info"
  log=$(cd "$ROOT/$dir" && flutter test --no-pub --reporter compact --timeout 120s --coverage --coverage-package '^(muyon|muyon_module_api|muyon_ui|muyon_ui_preview|prototype_module|research_module|supplier_core|inquiry_module)$' --coverage-path "$COVERAGE_DIR/$name/lcov.info" "$target" 2>&1; echo "exit=$?")
  code=${log##*exit=}
  log=$(echo "$log" | tr '\r' '\n')
  summary=$(echo "$log" | grep -E "All tests passed|Some tests failed|All other tests passed" | tail -1 | sed -E 's/^[0-9:]+ //')
  python3 - "$COVERAGE_DIR/suite-summary.json" "$name" "$code" "$summary" <<'PY_SUMMARY'
import json, re, sys
from pathlib import Path
path = Path(sys.argv[1])
rows = json.loads(path.read_text())
summary = sys.argv[4]
skips = re.search(r'~([0-9]+)', summary)
rows.append(dict(suite=sys.argv[2], exit_code=int(sys.argv[3]),
                 summary=summary, skipped=int(skips.group(1)) if skips else 0,
                 skip_reason_attribution='unknown; inspect test declarations/logs'))
path.write_text(json.dumps(rows, indent=2) + '\n')
PY_SUMMARY
  if [[ "$code" -eq 0 && -n "$summary" ]]; then
    echo "test     $name: ok  $summary"
    test_ok=$((test_ok + 1))
  else
    echo "test     $name: FAILED (exit $code)  ${summary:-NO SUMMARY (crashed or hung)}"
    # Everything except the per-test progress lines of passing tests, so load
    # errors and stack traces stay visible.
    echo "$log" | grep -vE '^[0-9]+:[0-9]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: .*[^]]$' | sed 's/^/           /'
    status=1; failed+=("test:$name")
  fi
done

coverage_args=(--reports "$COVERAGE_DIR" --output "$COVERAGE_DIR/summary.json" --baseline "$ROOT/scripts/coverage/baseline.json")
if ! python3 "$ROOT/scripts/coverage/test_check.py"; then
  status=1; failed+=("coverage:fixtures")
fi
if ! python3 "$ROOT/scripts/coverage/check.py" "${coverage_args[@]}"; then
  status=1; failed+=("coverage:report")
fi

if [[ $status -eq 0 ]]; then
  echo "CI SUMMARY: OK (analyze $analyze_ok/$analyze_total, test $test_ok/$test_total suites)"
else
  echo "CI SUMMARY: FAILED (${failed[*]})"
fi
exit $status
