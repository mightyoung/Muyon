#!/usr/bin/env bash
set -euo pipefail
root=/workspace/leaderb-a
state="$root/experiments/redesign/android-compose-lab/state/src/main/kotlin/com/mightyoung/muyon/androidlab"
source="$root/apps/muyon/android/agent-observation/src"
/workspace/a-tools/kotlinc/bin/kotlinc "$state/AgentServiceContract.kt" "$state/AgentServiceClientState.kt" "$state/AgentServiceWire.kt" "$source/main/kotlin/com/mightyoung/muyon/agent/ReceiptObserver.kt" "$source/test/kotlin/com/mightyoung/muyon/agent/ReceiptObserverChecks.kt" -jvm-target 17 -include-runtime -d /workspace/leaderb-evidence/a/receipt-checks.jar
java -jar /workspace/leaderb-evidence/a/receipt-checks.jar
