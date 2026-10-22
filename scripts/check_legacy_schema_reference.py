#!/usr/bin/env python3
"""Check immutable schema12 test references; never fetch or execute Dart."""
import hashlib
import json
from pathlib import Path
import sys

SOURCE = '214b4031deb38ca7dfd35ee86396089eb48157d5'
NAMES = {'store.dart', 'entities.dart'}


def check(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if manifest.get('schema_version') != 1 or manifest.get('source_sha') != SOURCE:
        raise ValueError('unexpected reference version/source')
    if set(manifest.get('files', {})) != NAMES:
        raise ValueError('reference inventory differs')
    for name, entry in manifest['files'].items():
        if entry['source_path'] != 'packages/supplier_core/lib/src/' + name:
            raise ValueError('unexpected historical source path')
        data = (directory / name).read_bytes()
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('reference bytes differ: ' + name)


if __name__ == '__main__':
    directory = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1] / 'experiments/redesign/rust-agent-host-lab/core/tests/fixtures/legacy-schema12'
    try:
        check(directory)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('Legacy schema reference: FAILED: ' + str(error), file=sys.stderr)
        sys.exit(1)
    print('Legacy schema reference: PASS (frozen bytes only; no Dart execution)')
