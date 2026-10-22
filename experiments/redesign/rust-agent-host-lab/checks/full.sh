#!/usr/bin/env bash
# Required offline execution; evidence lives outside the checkout.
set -euo pipefail
component=$1
checks=experiments/redesign/rust-agent-host-lab/checks
core=experiments/redesign/core-agent-lab/core
plugin=experiments/redesign/plugin-contract-lab/core
case "$component" in
  core) manifest="$core/Cargo.toml" ;;
  plugin) manifest="$plugin/Cargo.toml" ;;
  host) manifest=experiments/redesign/rust-agent-host-lab/core/Cargo.toml ;;
  *) exit 2 ;;
esac
: "${EVIDENCE_DIR:?}" "${CARGO_TARGET_DIR:?}"
mkdir -p "$EVIDENCE_DIR"
set -o pipefail
cargo test --offline --locked --no-run --manifest-path "$manifest" 2>&1 | tee "$EVIDENCE_DIR/compile.log"
if [[ "$component" == core ]]; then
  cargo build --offline --locked --release --manifest-path "$manifest" --bin muyon-core-agent-lab 2>&1 | tee "$EVIDENCE_DIR/build.log"
  binary="$CARGO_TARGET_DIR/release/muyon-core-agent-lab"
else
  cargo build --offline --locked --manifest-path "$plugin/Cargo.toml" --bin muyon-plugin-contract-lab 2>&1 | tee "$EVIDENCE_DIR/build.log"
  binary="$CARGO_TARGET_DIR/debug/muyon-plugin-contract-lab"
  export MUYON_PLUGIN_CONTRACT_BIN="$binary"
fi
test -x "$binary"
# Includes actual integration-test executables and protocol fixture, not just a facade bin.
find "$CARGO_TARGET_DIR" -type f -executable -print0 | sort -z | xargs -0 sha256sum > "$EVIDENCE_DIR/binary-sha256.txt"
set +e
cargo test --offline --locked --no-fail-fast --manifest-path "$manifest" 2>&1 | tee "$EVIDENCE_DIR/behavior.log"
command_statuses=("${PIPESTATUS[@]}")
set -e
if (( command_statuses[1] != 0 )); then exit "${command_statuses[1]}"; fi
python3 -B "$checks/full.py" rust --contract combined --name "$component" --log "$EVIDENCE_DIR/behavior.log" --status "${command_statuses[0]}" --output "$EVIDENCE_DIR/behavior-verdict.json"
if (( command_statuses[0] != 0 )); then exit "${command_statuses[0]}"; fi
if [[ "$component" != core ]]; then exit 0; fi

# Core115 preserves legacy90/native6/HTTP11 plus eight durable HTTP cases. The following
# physical process44 and harness13 gates are separate obligations, not Rust cases.
for suite in test_harness test_wire_harness process wire_process; do
  arguments=()
  if [[ "$suite" == process || "$suite" == wire_process ]]; then
    arguments=(--binary "$binary" --evidence-dir "$EVIDENCE_DIR/$suite")
  fi
  set +e
  python3 -B "experiments/redesign/core-agent-lab/checks/$suite.py" "${arguments[@]}" 2>&1 | tee "$EVIDENCE_DIR/$suite.log"
  command_statuses=("${PIPESTATUS[@]}")
  set -e
  if (( command_statuses[1] != 0 )); then exit "${command_statuses[1]}"; fi
  python3 -B "$checks/full.py" python --name "$suite" --log "$EVIDENCE_DIR/$suite.log" --status "${command_statuses[0]}" --output "$EVIDENCE_DIR/$suite-verdict.json"
  if (( command_statuses[0] != 0 )); then exit "${command_statuses[0]}"; fi
done
# The existing runner mutates private copies only. Never share our baseline
# target directory with those copies. Missing anchors/build/timeout stay INVALID.
set +e
env -u CARGO_TARGET_DIR python3 -B "$core/mutations.py" --evidence-dir "$EVIDENCE_DIR/mutations" 2>&1 | tee "$EVIDENCE_DIR/mutations.log"
command_statuses=("${PIPESTATUS[@]}")
set -e
if (( command_statuses[1] != 0 )); then exit "${command_statuses[1]}"; fi
python3 -B "$checks/full.py" mutants --name legacy17 --log "$EVIDENCE_DIR/mutations/summary.json" --status "${command_statuses[0]}" --output "$EVIDENCE_DIR/mutations-verdict.json"
if (( command_statuses[0] != 0 )); then exit "${command_statuses[0]}"; fi

# Precise target/source-line semantics supplement every historical broad Rust inverse.
python3 -B "$checks/legacy_precise.py" --source-root "$PWD" --evidence-dir "$EVIDENCE_DIR/legacy-precise" --work-dir "$EVIDENCE_DIR/legacy-precise-work"
