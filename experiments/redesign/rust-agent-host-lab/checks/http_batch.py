"""Separate HTTP batch contract; never replaces product acceptance."""
import copy
from full import CASES, rust


def contract():
    value = copy.deepcopy(CASES)
    core = value['components']['core']
    core['groups']['integration:native_ports']['names'].extend([
        'host_wire_charges_share_budget_and_host_journal',
        'host_wire_budget_rejects_without_charging_excess',
        'host_persist_failure_and_inflight_prevent_provider_entry',
        'host_charge_persistence_failure_stops_exchange_and_keeps_charged_bytes',
        'host_transport_total_also_bounds_response_and_next_admission',
    ])
    core['groups']['integration:native_runtime_restore'] = dict(family='http-durable-restore', names=[
        'native_host_metered_terminal_reopens_with_original_identity_and_counters',
        'native_host_discriminator_rejects_script_config_history_and_pending_call',
        'native_host_discriminator_rejects_unaccounted_or_over_budget_wire_bytes',
    ])
    core['expected_total'] = 115
    host = value['components']['host']
    host['groups']['integration:host_http'] = dict(family='host-synthetic-http', names=[
        'loopback_answer_uses_gateway_review_and_shared_durable_budget',
        'loopback_truncation_cancellation_and_revocation_never_resend',
        'loopback_budget_and_initial_authority_refuse_before_socket_bytes',
        'loopback_unknown_inflight_crash_blocks_same_state_retry',
        'loopback_receive_budget_stops_partial_response_without_retry',
        'loopback_mismatched_session_refuses_before_ledger_or_connection',
    ])
    host['groups']['unit:src/lib.rs']['names'].extend('http_recovery_tests::' + name for name in [
        'http_recovery_child',
        'loopback_cross_process_crash_preserves_unknown_begin_without_resend',
        'loopback_post_io_sent_ledger_failure_recovers_unknown_without_resend',
        'loopback_post_io_failed_ledger_overrides_cancel_and_recovers_unknown_without_resend',
        'loopback_post_io_wire_journal_is_unknown_without_resend',
    ])
    host['expected_total'] = 59
    return value


def classify(component, text, status):
    return rust(component, text, status, contract=contract())


def inverse(text, record, target, needles):
    import re
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', text, re.M)
    return (record['exit_code'] == 101 and record['timed_out'] is False
            and record['forced_owned_group_cleanup'] is False and record['live_after_cleanup'] == []
            and re.search(r'^test ' + re.escape(target) + r' \.\.\. FAILED$', text, re.M) is not None
            and bool(summaries) and summaries[-1][:5] == ('FAILED', '0', '1', '0', '0')
            and all(needle in text for needle in needles)
            and not re.search(r'could not compile|SIGABRT|SIGKILL|signal:|timed out', text))


def main():
    import argparse
    import hashlib
    import json
    import os
    from pathlib import Path
    import subprocess
    import sys
    parser = argparse.ArgumentParser()
    for name in ('source-root', 'evidence-dir', 'target-dir'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--expected-source', help='Explicit immutable candidate; omitted preserves historical exact8e contract')
    args = parser.parse_args()
    source = '8e0f6b1d0abfb0115bf48fa0bc8c790bfe30fa16'
    source = args.expected_source or source
    root, evidence = args.source_root.resolve(), args.evidence_dir.resolve()
    from source_identity import validate
    validate(root, source)
    evidence.mkdir(parents=True)
    def git(*parts):
        return subprocess.check_output(['git', *parts], cwd=root, text=True).strip()
    if git('rev-parse', 'HEAD') != source or git('status', '--porcelain'):
        raise RuntimeError('exact_clean_http_source_required')
    before = git('rev-parse', 'HEAD^{tree}')
    android_checks = Path(__file__).resolve().parents[2] / 'android-rust-bridge-lab/checks'
    sys.path.insert(0, str(android_checks))
    from linux_gate import run, sha
    env = dict(os.environ, CARGO_TARGET_DIR=str(args.target_dir.resolve()), CARGO_INCREMENTAL='0')
    if 'RUST_TEST_THREADS' in env:
        raise RuntimeError('default_parallel_required')
    labs = {'core': 'core-agent-lab', 'plugin': 'plugin-contract-lab', 'host': 'rust-agent-host-lab'}
    plugin = root / 'experiments/redesign/plugin-contract-lab/core'
    run(['cargo', 'build', '--offline', '--locked', '--bin', 'muyon-plugin-contract-lab'], evidence / 'plugin-build.log', env, cwd=plugin)
    env['MUYON_PLUGIN_CONTRACT_BIN'] = str(args.target_dir.resolve() / 'debug/muyon-plugin-contract-lab')
    rows = []
    for component, lab in labs.items():
        log = evidence / (component + '.log')
        status = run(['cargo', 'test', '--offline', '--locked', '--no-fail-fast'], log, env,
                     cwd=root / 'experiments/redesign' / lab / 'core', required=False)
        result = classify(component, log.read_text(), status)
        result.update(source_sha=source, source_tree=before, raw_sha256=sha(log))
        (evidence / (component + '-verdict.json')).write_text(json.dumps(result, indent=2) + '\n')
        rows.append(result)
    unchanged = (git('rev-parse', 'HEAD') == source and git('rev-parse', 'HEAD^{tree}') == before and not git('status', '--porcelain'))
    result = dict(source_sha=source, source_tree=before, default_parallel=True,
                  source_inputs_unchanged=unchanged, components=rows,
                  accepted=unchanged and all(row['accepted'] for row in rows))
    (evidence / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
