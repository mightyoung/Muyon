"""Frozen reachable-assertion RED contracts, independent of DUT output."""
import argparse
import hashlib
import json
from pathlib import Path
import re

CORE = 'experiments/redesign/core-agent-lab/core'
PLUGIN = 'experiments/redesign/plugin-contract-lab/core'
CONTRACTS = {
    'core-red': dict(crate=CORE, binary='muyon-core-agent-lab', target='native_ports',
        test='generic_ports_share_driver_without_inquiry_names', filtered=0,
        reach='NATIVE_PORT_STUB_REACHED persists=1 dispatches=0',
        assertion='NATIVE_PORT_RED: registered generic read reaches the shared driver',
        contract_source='52c59fbb33dbb73300e37689c4bcaab145bc10aa'),
    'protocol-red': dict(crate=CORE, binary='muyon-core-agent-lab', target='native_protocol',
        test='registered_protocol_preserves_arguments_and_schema', filtered=3,
        reach='NATIVE_PROTOCOL_STUB_REACHED',
        assertion='NATIVE_PROTOCOL_RED: registered schema reaches native payload',
        contract_source='ba3a4a0472c33d999c302e79569a7f9a00dc9c15'),
    'plugin-red': dict(crate=PLUGIN, binary='muyon-plugin-contract-lab', target='mapping_contract',
        test='native_declarations_register_without_grants_or_reads', filtered=1,
        reach='NATIVE_PLUGIN_MAPPING_STUB_REACHED code=native_mapping_unsupported',
        assertion='RUST_NATIVE_PLUGIN_MAPPING_RED: registered native declaration required',
        contract_source='d0c1269c2acc405663ef7a50a75d3652786ccd2e'),
}


def classify(suite, text, exit_code):
    c = CONTRACTS[suite]
    compiled = bool(re.search(r'Finished [^\n]*test[^\n]*profile', text))
    rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', text, re.M)
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', text, re.M)
    panic = list(re.finditer(r"^thread '([^']+)'(?: \(\d+\))? panicked at [^\n]+:\n([^\n]*)", text, re.M))
    guards = list(re.finditer('^' + re.escape(c['reach']) + '$', text, re.M))
    targets = re.findall(r'^\s*Running tests/(\w+)\.rs\s+\(', text, re.M)
    reached = (len(guards) == 1 and len(panic) == 1 and guards[0].start() < panic[0].start())
    assertion = (len(panic) == 1 and panic[0].group(1) == c['test']
                 and c['assertion'] in panic[0].group(2))
    accepted = (compiled and reached and assertion and exit_code == 101
        and targets == [c['target']] and rows == [(c['test'], 'FAILED')]
        and summaries == [('FAILED', '0', '1', '0', '0', str(c['filtered']))]
        and not re.search(r'timed out|TimeoutException|SIGABRT|SIGKILL', text, re.I))
    return dict(suite=suite, contract=c, compiled=compiled, reached=reached,
        assertion=assertion, observed_tests=len(rows), expected_tests=1,
        command_exit_code=exit_code, accepted=accepted,
        classification='semantic_red' if accepted else 'INVALID',
        red_requires_ci_failure=True, native_host_closure='NOT_RUN', legacy_runtime_baselines='NOT_RUN')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['describe', 'classify'])
    parser.add_argument('--suite', choices=CONTRACTS, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--github-env', type=Path)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--exit-code', type=int)
    args = parser.parse_args()
    if args.action == 'describe':
        result = CONTRACTS[args.suite]
        if args.github_env:
            with args.github_env.open('a') as output:
                for key, value in dict(MANIFEST=result['crate'] + '/Cargo.toml',
                    BINARY=result['binary'], TEST_TARGET=result['target'], TEST_NAME=result['test'],
                    BINARY_PATH=result['crate'] + '/target/debug/' + result['binary']).items():
                    output.write(key + '=' + value + '\n')
    else:
        raw = args.log.read_bytes() if args.log and args.log.is_file() else b''
        result = classify(args.suite, raw.decode(errors='replace'), args.exit_code)
        result['raw_sha256'] = hashlib.sha256(raw).hexdigest()
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if args.action == 'describe' or result['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
