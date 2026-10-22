"""Select full by default; immutable RED refs retain their explicit suite."""
import argparse
import json


def select(suite, ref):
    if not suite:
        suite = next((name for name in ['host-red', 'core-red', 'protocol-red', 'plugin-red', 'red'] if ref.startswith('lab/rust-native-read-' + name + '-')), 'full')
    if suite not in ['full', 'red', 'host-red', 'core-red', 'protocol-red', 'plugin-red']:
        raise ValueError('unknown suite')
    return ('full', []) if suite == 'full' else ('red', ['core-red', 'protocol-red', 'plugin-red'] if suite == 'red' else [suite])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', default='')
    parser.add_argument('--ref', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    mode, matrix = select(args.suite, args.ref)
    with open(args.output, 'a') as output:
        output.write('mode=' + mode + '\nred=' + json.dumps(matrix) + '\n')
