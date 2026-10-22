"""Separate immutable host46 diagnostic gate; legacy45 and temp46 RED stay unchanged."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import host_checkpoint

HERE = Path(__file__).resolve().parent
DESCRIPTOR = HERE / 'service_host_46_green_cases.json'
CONTRACT = json.loads(DESCRIPTOR.read_text())
CORE = 'experiments/redesign/rust-agent-host-lab/core'


def inventory(root):
    expected = set()
    for name, group in CONTRACT['targets'].items():
        if group['path'] != CORE + '/tests/' + name + '.rs':
            raise RuntimeError('service_host46_inventory_invalid')
        raw = (root / group['path']).read_bytes()
        names = re.findall(r'#\[test\]\s*fn\s+(\w+)\s*\(', raw.decode())
        if (hashlib.sha256(raw).hexdigest() != group['sha256']
            or hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() != group['blob_sha']
            or names != group['names'] or len(set(names)) != len(names)):
            raise RuntimeError('service_host46_inventory_invalid')
        expected.add(group['path'])
    actual = {str(p.relative_to(root)) for p in (root / CORE / 'tests').rglob('*.rs')}
    if expected != actual or sum(len(g['names']) for g in CONTRACT['targets'].values()) != 46:
        raise RuntimeError('service_host46_inventory_invalid')


def classify(target, raw, status):
    previous = host_checkpoint.GREEN_CONTRACT
    try:
        host_checkpoint.GREEN_CONTRACT = CONTRACT
        return host_checkpoint.target_green(target, raw, status, service=True)
    finally:
        host_checkpoint.GREEN_CONTRACT = previous


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=HERE.parents[3])
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    args = parser.parse_args()
    work = args.work_dir.resolve(); work.mkdir(parents=True, exist_ok=False)
    evidence = args.evidence_dir.resolve(); evidence.mkdir(parents=True, exist_ok=False)
    archive = subprocess.check_output(['git', 'archive', CONTRACT['source_commit'], *['experiments/redesign/' + n for n in ['rust-agent-host-lab', 'core-agent-lab', 'plugin-contract-lab']]], cwd=args.repo)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(work, filter='data')
    inventory(work)
    env = dict(os.environ, CARGO_TERM_COLOR='never', CARGO_INCREMENTAL='0')
    command_base = ['cargo', '+1.99.0']
    def run(words, name):
        with (evidence / name).open('w') as log:
            try:
                return subprocess.run(words, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=900).returncode
            except subprocess.TimeoutExpired:
                return 124
    host = work / CORE / 'Cargo.toml'
    plugin = work / 'experiments/redesign/plugin-contract-lab/core/Cargo.toml'
    result = dict(accepted=False, classification='INVALID', source_commit=CONTRACT['source_commit'], shipping_or_service_green=False,
        descriptor_sha256=hashlib.sha256(DESCRIPTOR.read_bytes()).hexdigest(), targets=[], executed_tests=0)
    if run(command_base + ['build', '--release', '--locked', '--manifest-path', str(plugin), '--bin', 'muyon-plugin-contract-lab'], 'plugin-build.log') == 0:
        target = Path(env.get('CARGO_TARGET_DIR', str(plugin.parent / 'target')))
        env['MUYON_PLUGIN_CONTRACT_BIN'] = str(target / 'release/muyon-plugin-contract-lab')
        for name in CONTRACT['targets']:
            log = evidence / (name + '.log')
            status = run(command_base + ['test', '--release', '--locked', '--offline', '--manifest-path', str(host), '--test', name], log.name)
            row = classify(name, log.read_text(errors='replace'), status)
            row['raw_sha256'] = hashlib.sha256(log.read_bytes()).hexdigest()
            result['targets'].append(row); result['executed_tests'] += row['observed_tests']
        result['accepted'] = all(r['accepted'] for r in result['targets']) and result['executed_tests'] == 46
        if result['accepted']:
            result['classification'] = 'diagnostic_host46_green'
    inventory(work)
    (evidence / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    raise SystemExit(0 if result['accepted'] else 1)


if __name__ == '__main__':
    main()
