"""Source-fixed host checkpoints and Rust Service groups; Android runtime is separate."""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

CONTRACT = json.loads(Path(__file__).with_name('host_checkpoint_cases.json').read_text())
TARGET_COUNTS = dict(native_read=25, contract_transport=8, service_runtime=2, service_root=2)
GREEN_CONTRACT = json.loads(Path(__file__).with_name('service_host_green_cases.json').read_text())
GREEN_COUNTS = dict(TARGET_COUNTS, service_controller=4, service_oracle=1, service_lifecycle=3)
PREFIX = 'experiments/redesign/rust-agent-host-lab/core/'


def inventory(root, contract=None, *, service=False):
    contract = (GREEN_CONTRACT if service else CONTRACT) if contract is None else contract
    counts = GREEN_COUNTS if service else TARGET_COUNTS
    try:
        if (set(contract) != {'version', 'author_commit', 'manifest', 'targets', 'not_run'}
                or type(contract['version']) is not int or contract['version'] != 1
                or not re.fullmatch('[0-9a-f]{40}', contract['author_commit'])
                or contract['manifest'] != PREFIX + 'Cargo.toml'
                or set(contract['targets']) != set(counts)
                or set(contract['not_run']) != (set() if service else {'service_controller'})):
            raise ValueError('shape')
        for target, group in (contract['targets'] | contract['not_run']).items():
            count = counts.get(target, 4)
            if (set(group) != {'path', 'blob_sha', 'sha256', 'names'}
                    or group['path'] != PREFIX + 'tests/' + target + '.rs'
                    or not re.fullmatch('[0-9a-f]{40}', group['blob_sha'])
                    or not re.fullmatch('[0-9a-f]{64}', group['sha256'])
                    or not isinstance(group['names'], list) or len(group['names']) != count
                    or len(set(group['names'])) != count
                    or not all(isinstance(n, str) and re.fullmatch(r'[A-Za-z_]\w*', n) for n in group['names'])):
                raise ValueError('group')
            data = (root / group['path']).read_bytes()
            blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            names = re.findall(r'#\[test\]\s*fn\s+(\w+)\s*\(', data.decode('utf-8'))
            if (hashlib.sha256(data).hexdigest() != group['sha256'] or blob != group['blob_sha']
                    or Counter(names) != Counter(group['names'])):
                raise ValueError('source')
        if service:
            actual = {str(p.relative_to(root)) for p in (root / PREFIX / 'tests').rglob('*.rs')}
            if actual != {group['path'] for group in contract['targets'].values()}:
                raise ValueError('unknown integration source')
        return contract
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as failure:
        raise RuntimeError('host_checkpoint_inventory_invalid') from failure


def target_green(target, raw, status, *, service=False):
    group = (GREEN_CONTRACT if service else CONTRACT)['targets'].get(target)
    rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', raw, re.M)
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', raw, re.M)
    targets = re.findall(r'^\s*Running tests/(\w+)\.rs \(', raw, re.M)
    valid = bool(group and status == 0 and re.search(r'Finished `release` profile', raw)
        and targets == [target]
        and Counter(rows) == Counter((name, 'ok') for name in group['names'])
        and summaries == [('ok', str(len(group['names'])), '0', '0', '0', '0')]
        and not re.search(r'could not compile|error\[E\d+\]|panicked at|timed out|signal:|\ufffd', raw))
    return dict(accepted=valid, classification='checkpoint_target_green' if valid else 'INVALID',
                target=target, command_exit_code=status, observed_tests=len(rows),
                expected_tests=len(group['names']) if group else None)


ORACLE = json.loads(Path(__file__).with_name('service_oracle_red_cases.json').read_text())


def oracle_inventory(root, contract=None):
    contract = ORACLE if contract is None else contract
    try:
        if (set(contract) != {'version', 'author_commit', 'path', 'blob_sha', 'sha256', 'red'}
                or type(contract['version']) is not int or contract['version'] != 1
                or not re.fullmatch('[0-9a-f]{40}', contract['author_commit'])
                or contract['path'] != PREFIX + 'tests/service_oracle.rs'
                or not re.fullmatch('[0-9a-f]{40}', contract['blob_sha'])
                or not re.fullmatch('[0-9a-f]{64}', contract['sha256'])
                or contract['red'] != ORACLE['red']):
            raise ValueError('shape')
        data = (root / contract['path']).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if (hashlib.sha256(data).hexdigest() != contract['sha256'] or blob != contract['blob_sha']
                or re.findall(r'#\[test\]\s*fn\s+(\w+)\s*\(', data.decode('utf-8')) != [contract['red']['test']]):
            raise ValueError('source')
        return contract
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as failure:
        raise RuntimeError('service_oracle_inventory_invalid') from failure


def oracle_red(raw, status, source, binary_sha):
    # Reuse the reviewed strict Rust panic/row/summary/correlation classifier;
    # this mode has no JVM phase or corresponding markers.
    from ffi_evidence import service_red
    red = dict(ORACLE['red'], jvm_reach='NOT_APPLICABLE', jvm_assert='NOT_APPLICABLE')
    result = service_red('service-rust-red', raw, status, source, binary_sha, red)
    result.update(mode='service-oracle-red',
                  scope='controller entry/refusal only; worker/observer execution not reached')
    return result
