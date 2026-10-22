"""Exact early compiled RED classification; metadata success never washes CI GREEN."""
import argparse
import hashlib
import json
from pathlib import Path
import re

RUST_TEST = 'bundled_contract_reaches_rust_catalog'
RUST_REACH = 'ANDROID_BRIDGE_STUB_REACHED code=internal_failure'
RUST_ASSERT = 'ANDROID_BRIDGE_RED: bundled declaration must be registered and inspected in Rust'
JVM_REACH = 'ANDROID_BRIDGE_JVM_STUB_REACHED code=internal_failure'
JVM_ASSERT = 'ANDROID_BRIDGE_JVM_RED: actual Rust bundled declaration must validate'
SERVICE_MODES = ['service-rust-red', 'service-jvm-red']


def service_red(mode, raw, status, source, library_sha, contract):
    keys = {'target', 'test', 'filtered', 'native_reach', 'rust_assert', 'jvm_reach', 'jvm_assert'}
    valid_contract = (isinstance(contract, dict) and set(contract) == keys
        and type(contract['filtered']) is int and contract['filtered'] >= 0
        and all(isinstance(contract[key], str) and re.fullmatch(r'[A-Za-z_]\w*', contract[key])
                for key in ['target', 'test'])
        and all(isinstance(contract[key], str) and 0 < len(contract[key]) <= 512
                and contract[key].isascii() and '\n' not in contract[key] and '\r' not in contract[key]
                for key in ['native_reach', 'rust_assert', 'jvm_reach', 'jvm_assert']))
    identity = bool(re.fullmatch('[0-9a-f]{40}', source) and re.fullmatch('[0-9a-f]{64}', library_sha))
    no_fault = not re.search(r'Timeout|timed out|SIGABRT|SIGKILL|signal:|could not compile|error\[E\d+\]|UnsatisfiedLinkError|NoClassDefFoundError|checksum mismatch|\ufffd', raw)
    valid = False
    if valid_contract and identity and no_fault:
        reach = contract['native_reach']
        if mode == 'service-rust-red':
            # Count headers independently of message content: an auxiliary
            # empty-message panic must not disappear from the failure oracle.
            panic_headers = re.findall(r"^thread '([^']*)'(?: \(\d+\))? panicked at\b", raw, re.M)
            panics = re.findall(r"thread '([^']+)'(?: \(\d+\))? panicked at [^\n]+:\n([^\n]+)", raw)
            rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', raw, re.M)
            summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', raw, re.M)
            valid = (status == 101 and 'Finished `release` profile' in raw
                and len(re.findall(r'Running tests/' + re.escape(contract['target']) + r'\.rs \(', raw)) == 1
                and panic_headers == [contract['test']]
                and panics == [(contract['test'], contract['rust_assert'])]
                and rows == [(contract['test'], 'FAILED')]
                and summaries == [('FAILED', '0', '1', '0', '0', str(contract['filtered']))]
                and raw.splitlines().count(reach) == 1 and raw.index(reach) < raw.index("thread '"))
        elif mode == 'service-jvm-red':
            mapped = f'AGENT_SERVICE_JVM_MAPPED source={source} sha256={library_sha}'
            # No auxiliary uncaught Java exception is valid service RED either.
            # Enumerate all headers, not only the expected main exception type.
            failures = re.findall(r'^Exception in thread "([^"]*)"([^\n]*)', raw, re.M)
            primary = 'Exception in thread "main" java.lang.IllegalStateException: ' + contract['jvm_assert']
            markers = [mapped, reach, contract['jvm_reach']]
            valid = (status == 1 and failures == [('main', ' java.lang.IllegalStateException: ' + contract['jvm_assert'])]
                and all(raw.splitlines().count(marker) == 1 for marker in markers)
                and all(raw.index(first) < raw.index(second)
                        for first, second in zip(markers, markers[1:] + [primary]))
                and not re.search(r'^AGENT_SERVICE_JVM_PASS ', raw, re.M))
    return dict(accepted=bool(valid), classification='semantic_red' if valid else 'INVALID',
        mode=mode, command_exit_code=status,
        scope='actual service Rust controller' if mode == 'service-rust-red' else
              'actual generated Kotlin/JNA shipping service controller; Android Binder/process runtime NOT_RUN')


def classify(mode, raw, status, source, library_sha, service=None):
    if mode in SERVICE_MODES:
        return service_red(mode, raw, status, source, library_sha, service)
    no_fault = not re.search(r'Timeout|timed out|SIGABRT|SIGKILL|signal:|UnsatisfiedLinkError|NoClassDefFoundError|checksum mismatch', raw)
    if mode == 'rust-red':
        panics = re.findall(r"thread '([^']+)'(?: \(\d+\))? panicked at [^\n]+:\n([^\n]+)", raw)
        rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', raw, re.M)
        summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', raw, re.M)
        valid = (status == 101 and no_fault and 'Finished `release` profile' in raw
                 and len(re.findall(r'Running tests/bridge_contract\.rs \(', raw)) == 1
                 and panics == [(RUST_TEST, RUST_ASSERT)] and rows == [(RUST_TEST, 'FAILED')]
                 and summaries == [('FAILED', '0', '1', '0', '0', '5')]
                 and raw.count(RUST_REACH) == 1 and raw.index(RUST_REACH) < raw.index("thread '"))
    else:
        mapped = f'ANDROID_BRIDGE_JVM_MAPPED source={source} sha256={library_sha}'
        failures = re.findall(r'^Exception in thread "main" java\.lang\.IllegalStateException: ([^\n]+)', raw, re.M)
        valid = (status == 1 and no_fault and failures == [JVM_ASSERT]
                 and all(raw.count(marker) == 1 for marker in [mapped, RUST_REACH, JVM_REACH])
                 and all(raw.index(marker) < raw.index('Exception in thread') for marker in [mapped, RUST_REACH, JVM_REACH])
                 and not re.search(r'^ANDROID_BRIDGE_JVM_PASS ', raw, re.M))
    return dict(accepted=bool(valid), classification='semantic_red' if valid else 'INVALID',
                mode=mode, command_exit_code=status, scope='actual compiled Rust' if mode == 'rust-red' else 'actual generated Kotlin/JNA Linux native call; Android NOT_RUN')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['rust-red', 'jvm-red'], required=True)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--status', type=int, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raw = args.log.read_bytes()
    result = classify(args.mode, raw.decode('utf-8', errors='replace'), args.status, args.source, hashlib.sha256(args.library.read_bytes()).hexdigest())
    result.update(raw_sha256=hashlib.sha256(raw).hexdigest(), source_sha=args.source)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
