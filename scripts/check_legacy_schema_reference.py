#!/usr/bin/env python3
"""Check immutable schema12 test references; never fetch or execute Dart."""
import hashlib
import json
from pathlib import Path
import sys

SOURCE = '214b4031deb38ca7dfd35ee86396089eb48157d5'
# Fixed witnesses independently checked against SOURCE's Git objects. The
# manifest describes provenance; it cannot redefine the accepted bytes.
EXPECTED = {
    'store.dart': {
        'source_path': 'packages/supplier_core/lib/src/store.dart',
        'bytes': 23533,
        'sha256': 'c75c10d73db7f554290d02d11efda73045ddca22a2c1fd70bca1f60a403d0e3c',
        'git_blob': '6499d3afdbc394ab333bcbb0b41ed7eb537c92b2',
    },
    'entities.dart': {
        'source_path': 'packages/supplier_core/lib/src/entities.dart',
        'bytes': 6862,
        'sha256': 'aa9980a6cb84150d773e012c7a79e13ffda28efb1e170d78b86db01c9a052a46',
        'git_blob': '00c5e1d0e7393c13c823b6beff4402dc527f08be',
    },
}


def check(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if manifest.get('schema_version') != 1 or manifest.get('source_sha') != SOURCE:
        raise ValueError('unexpected reference version/source')
    if set(manifest.get('files', {})) != set(EXPECTED):
        raise ValueError('reference inventory differs')
    for name, witness in EXPECTED.items():
        if manifest['files'][name] != witness:
            raise ValueError('reference manifest differs from fixed witness: ' + name)
        with (directory / name).open('rb') as stream:
            data = stream.read(witness['bytes'] + 1)
        blob = b'blob ' + str(len(data)).encode('ascii') + b'\0' + data
        if (len(data) != witness['bytes']
                or hashlib.sha256(data).hexdigest() != witness['sha256']
                or hashlib.sha1(blob).hexdigest() != witness['git_blob']):
            raise ValueError('reference bytes differ: ' + name)


if __name__ == '__main__':
    directory = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1] / 'experiments/redesign/rust-agent-host-lab/core/tests/fixtures/legacy-schema12'
    try:
        check(directory)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('Legacy schema reference: FAILED: ' + str(error), file=sys.stderr)
        sys.exit(1)
    print('Legacy schema reference: PASS (frozen bytes only; no Dart execution)')
