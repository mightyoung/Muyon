#!/usr/bin/env bash
# Current delivery needs persisted document-core hooks; the earlier ab9c verifier
# and its historical raw results are superseded by the durable exact-core script.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec bash "$script_dir/verify-durable-combination.sh" "$@"
