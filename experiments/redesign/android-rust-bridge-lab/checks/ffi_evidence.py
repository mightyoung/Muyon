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


def classify(mode, raw, status, source, library_sha):
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
