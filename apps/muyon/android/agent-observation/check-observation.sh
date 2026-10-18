#!/usr/bin/env bash
set -euo pipefail
module=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$module/../../../.." && pwd)
state="$repo/experiments/redesign/android-compose-lab/state/src/main/kotlin/com/mightyoung/muyon/androidlab"
output=${MUYON_OBSERVATION_OUTPUT:-/tmp/muyon-receipt-observation-checks}
mkdir -p "$output"
"${MUYON_UI_KOTLINC:-kotlinc}" "$state/AgentServiceContract.kt" "$state/AgentServiceClientState.kt" "$state/AgentServiceWire.kt" \
  "$module/src/main/kotlin/com/mightyoung/muyon/agent/ReceiptObserver.kt" \
  "$module/src/test/kotlin/com/mightyoung/muyon/agent/ReceiptObserverChecks.kt" \
  -jvm-target 17 -include-runtime -d "$output/checks.jar"
"${MUYON_UI_JAVA:-java}" -jar "$output/checks.jar"
