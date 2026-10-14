"""Semantic inverse mutations in external temporary copies, never product changes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MUTATIONS = [
    ('bypass_actual_value_check',
     "if check.get('state') != 'complete_assumption' or signal != 'none_assumption':",
     'if False:',
     'test_none_field_does_not_replace_actual_value_check'),
    ('require_Auto_rule_in_FullAllow',
     "if mode == 'FullAllow':\n        return result(purpose, 'eligible', 'eligible', sensitivity, reason='FullAllow_current_scope_assumption')",
     "if mode == 'FullAllow':\n        if policy.get('auto_risk_rule') != 'synthetic_frozen_assumption_for_routing_only':\n            return result(purpose, 'eligible', 'blocked_contract', sensitivity, reason='mutant_Auto_dependency')\n        return result(purpose, 'eligible', 'eligible', sensitivity, reason='FullAllow_current_scope_assumption')",
     'test_FullAllow_missing_Auto_rule_is_not_a_contract_block'),
    ('downgrade_commercial_lineage',
     'if category in inherited:',
     'if category in inherited and category != "commercial":',
     'test_none_target_does_not_downgrade_commercial_source'),
]


def run_mutations(evidence_dir):
    evidence_dir = evidence_dir.resolve()
    if evidence_dir == ROOT or ROOT in evidence_dir.parents:
        raise ValueError('raw mutation logs must be outside the repository')
    evidence_dir.mkdir(parents=True, exist_ok=True)
    original = (HERE / 'seam.py').read_text()
    results = []
    for name, needle, replacement, failure in MUTATIONS:
        if original.count(needle) != 1:
            raise ValueError('mutation target changed: ' + name)
        with tempfile.TemporaryDirectory(prefix=name + '-', dir=evidence_dir) as tmp:
            isolated = Path(tmp)
            for filename in ['seam.py', 'fixture_adapter.py', 'driver.py', 'test_seam.py', 'test_driver.py']:
                (isolated / filename).write_bytes((HERE / filename).read_bytes())
            (isolated / 'seam.py').write_text(original.replace(needle, replacement, 1))
            proc = subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(isolated),
                                   '-p', 'test_*.py', '-v'], cwd=isolated, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            raw = proc.stdout
        log = evidence_dir / (name + '.log')
        log.write_text(raw)
        failed = re.findall(r'^FAIL: (test_[A-Za-z0-9_]+)', raw, re.MULTILINE)
        failures = re.search(r'FAILED \(failures=(\d+)', raw)
        ran = re.search(r'Ran (\d+) tests', raw)
        results.append({'name': name, 'exit': proc.returncode,
                        'tests_run': int(ran.group(1)) if ran else 0,
                        'assertion_failures': int(failures.group(1)) if failures else 0,
                        'failure_names': sorted(set(failed)), 'required_failure_name': failure,
                        'killed': proc.returncode == 1 and failure in failed,
                        'log_path': str(log), 'log_sha256': hashlib.sha256(raw.encode()).hexdigest()})
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = run_mutations(args.evidence_dir)
    report = {'kind': 'experimental_semantic_inverse_mutations', 'mutations': rows,
              'product_or_fixture_originals_mutated': False,
              'all_killed': all(r['killed'] for r in rows)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'mutation_count': len(rows), 'all_killed': report['all_killed'],
                      'exits': [r['exit'] for r in rows]}, sort_keys=True))
    return 0 if report['all_killed'] else 1


if __name__ == '__main__': sys.exit(main())
