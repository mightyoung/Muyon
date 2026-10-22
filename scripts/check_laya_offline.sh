#!/usr/bin/env bash
# Existing synthetic Laya tests only; no Flutter, user credentials or remote runs.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/scripts/laya"
for test_case in test_stage1_contract test_stage2_data test_stage2_threshold test_kaggle_submit; do
  python3 "$test_case.py"
done
