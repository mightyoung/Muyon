"""Exact isolated HTTP source and seven compiled behavioral inverses."""
import argparse
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
from http_batch import inverse

SOURCE = '8e0f6b1d0abfb0115bf48fa0bc8c790bfe30fa16'
HOST = 'experiments/redesign/rust-agent-host-lab/core'
CORE = 'experiments/redesign/core-agent-lab/core'
LIB = HOST + '/src/lib.rs'
AGENT = CORE + '/src/agent.rs'
RECOVERY = 'http_recovery_tests::'
MUTANTS = [
    ('budget_classification', LIB, 'if _reason == "wire_total_limit" {', 'if false && _reason == "wire_total_limit" {', HOST, ['--test', 'host_http'], 'loopback_receive_budget_stops_partial_response_without_retry', ['left: "failed"', 'right: "budget_exhausted"']),
    ('journal_classification', LIB, 'matches!(_reason, "model_ledger_failed" | "wire_journal")', 'matches!(_reason, "model_ledger_failed")', HOST, ['--lib'], RECOVERY + 'loopback_post_io_wire_journal_is_unknown_without_resend', ['left: ("failed", "native_host_refused")', 'right: ("outcome_unknown", "wire_journal")']),
    ('host_restore', AGENT, 'let wire_limit=if host_metered{limits.total}', 'let wire_limit=if host_metered{0}', CORE, ['--test', 'native_runtime_restore'], 'native_host_metered_terminal_reopens_with_original_identity_and_counters', ['invalid_wire_state', 'called `Result::unwrap()`']),
    ('inflight_unknown', AGENT, 'if state.wire_counters.inflight{state.stop(if state.host_metered{"outcome_unknown"}else{"failed"},"wire_interrupted");}', 'if state.wire_counters.inflight{state.stop("failed","wire_interrupted");}', HOST, ['--lib'], RECOVERY + 'loopback_cross_process_crash_preserves_unknown_begin_without_resend', ['left: ("failed", "wire_interrupted")', 'right: ("outcome_unknown", "wire_interrupted")']),
    ('completion_ledger_unknown', LIB, 'matches!(_reason, "model_ledger_failed" | "wire_journal")', 'matches!(_reason, "wire_journal")', HOST, ['--lib'], RECOVERY + 'loopback_post_io_sent_ledger_failure_recovers_unknown_without_resend', ['left: "failed"', 'right: "outcome_unknown"']),
    ('unknown_over_late_cancel', AGENT, 'if self.state.host_metered&&self.state.status=="outcome_unknown"{return self.save_drive(ports.as_deref());}', 'if false&&self.state.host_metered&&self.state.status=="outcome_unknown"{return self.save_drive(ports.as_deref());}', HOST, ['--lib'], RECOVERY + 'loopback_post_io_failed_ledger_overrides_cancel_and_recovers_unknown_without_resend', ['left: ("cancelled", "cancel_requested")', 'right: ("outcome_unknown", "model_ledger_failed")']),
    ('shared_charge', AGENT, 'if self.ports.is_some(){self.agent.state.counters.total=self.agent.state.counters.total.checked_add(bytes).ok_or("wire_total_limit")?;}', 'if false&&self.ports.is_some(){self.agent.state.counters.total=self.agent.state.counters.total.checked_add(bytes).ok_or("wire_total_limit")?;}', CORE, ['--test', 'native_ports'], 'host_wire_charges_share_budget_and_host_journal', ['host send uses the existing total budget', 'left: 9', 'right: 5']),
]


def main():
    parser = argparse.ArgumentParser()
    for name in ('source-root', 'evidence-dir', 'work-dir'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--expected-source', help='Explicit immutable candidate; omitted preserves historical exact8e archive')
    args = parser.parse_args()
    source = args.expected_source or SOURCE
    if args.expected_source:
        from source_identity import validate
        validate(args.source_root, source)
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'android-rust-bridge-lab/checks'))
    from linux_gate import run, sha
    evidence, work = args.evidence_dir.resolve(), args.work_dir.resolve()
    evidence.mkdir(parents=True); work.mkdir(parents=True)
    roots = ['experiments/redesign/' + name for name in ('core-agent-lab', 'plugin-contract-lab', 'rust-agent-host-lab')]
    archive = subprocess.check_output(['git', 'archive', source, *roots], cwd=args.source_root)
    copy = work / 'source'; copy.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        bundle.extractall(copy, filter='data')
    original = {path: (copy / path).read_text() for path in (LIB, AGENT)}
    env = dict(os.environ, CARGO_TARGET_DIR=str(work / 'target'), CARGO_INCREMENTAL='0')
    env['MUYON_PLUGIN_CONTRACT_BIN'] = str(work / 'target/debug/muyon-plugin-contract-lab')
    run(['cargo', 'build', '--offline', '--locked', '--bin', 'muyon-plugin-contract-lab'], evidence / 'plugin-build.log', env, cwd=copy / roots[1] / 'core')
    rows = []
    for name, path, before, after, crate, target_args, target, needles in MUTANTS:
        item = evidence / name; item.mkdir()
        for source_path, body in original.items():
            (copy / source_path).write_text(body)
        command = ['cargo', 'test', '--offline', '--locked', *target_args, target, '--', '--exact', '--nocapture']
        baseline_log = item / 'baseline.log'
        run(command, baseline_log, env, cwd=copy / crate, timeout=120)
        if f'test {target} ... ok' not in baseline_log.read_text():
            raise RuntimeError('missing_exact_baseline:' + name)
        if original[path].count(before) != 1:
            raise RuntimeError('mutation_anchor:' + name)
        (copy / path).write_text(original[path].replace(before, after))
        mutant_log = item / 'mutant.log'
        run(command, mutant_log, env, cwd=copy / crate, timeout=120, required=False)
        record = json.loads(mutant_log.with_suffix('.log.json').read_text())
        killed = inverse(mutant_log.read_text(), record, target, needles)
        rows.append(dict(name=name, target=target, baseline_green=True, mutation_killed=killed,
                         mutation_source_sha256=sha(copy / path), expected_needles=needles, mutant=record))
        (evidence / 'summary.json').write_text(json.dumps(dict(source_sha=source, rows=rows,
            accepted=len(rows) == len(MUTANTS) and all(row['mutation_killed'] for row in rows)), indent=2) + '\n')
        if not killed:
            raise RuntimeError('semantic_inverse_invalid:' + name)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
