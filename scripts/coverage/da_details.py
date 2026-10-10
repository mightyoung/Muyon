#!/usr/bin/env python3
"""Small DA diagnostics from existing reports; never a new baseline or gate."""
import argparse
import base64
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

_spec = importlib.util.spec_from_file_location('coverage_contract', Path(__file__).with_name('check.py'))
_contract = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_contract)
FILES = tuple('packages/muyon_module_api/lib/src/ui/' + name + '.dart'
              for name in ('snapshot', 'state', 'stream_compiler',
                           'stream_protocol', 'validation', 'workspace'))


def details(root, reports):
    data = {}
    missing = []
    for suite in _contract.SUITES:
        report = reports / suite / 'lcov.info'
        if not report.is_file():
            missing.append(suite)
            continue
        current = None
        for entry in report.read_text().splitlines():
            if entry.startswith('SF:'):
                source = Path(entry[3:])
                if not source.is_absolute():
                    source = root / _contract.WORKING_DIRS[suite] / source
                try:
                    path = source.resolve().relative_to(root.resolve()).as_posix()
                except ValueError:
                    path = None
                current = path if path and any(
                    path.startswith(package + '/lib/')
                    for package in _contract.PACKAGES) else None
            elif entry.startswith('DA:') and current:
                values = entry[3:].split(',')
                if len(values) < 2:
                    raise ValueError('incomplete DA record')
                line, hits = int(values[0]), int(values[1])
                if line < 1 or hits < 0:
                    raise ValueError('invalid DA record')
                loaded = data.setdefault(current, {})
                loaded[line] = loaded.get(line, False) or hits > 0
    files = {}
    for path in FILES:
        loaded = data.get(path)
        source = root / path
        files[path] = {
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest() if source.is_file() else None,
            'status': 'loaded_DA_records' if loaded else 'no_DA_records',
            'loaded_executable_lines': len(loaded) if loaded else 'unknown',
            'hit_lines': sum(loaded.values()) if loaded else 'unknown',
            'da_line_ids': sorted(loaded) if loaded else 'unknown',
            'uncovered_da_line_ids': sorted(n for n, hit in loaded.items() if not hit) if loaded else 'unknown',
        }
    return {
        'diagnostic_version': 1,
        'diagnostic_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'source_sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'report_union': 'existing eight suites; any hit at a source/line wins',
        'missing_suite_reports': missing,
        'files': files,
        'all_loaded_files': {
            path: {
                'source_sha256': hashlib.sha256((root / path).read_bytes()).hexdigest(),
                'da_line_ids': sorted(loaded),
                'uncovered_da_line_ids': sorted(n for n, hit in loaded.items() if not hit),
            }
            for path, loaded in sorted(data.items())
        },
        'limitations': [
            'DA comes only from LCOV, never physical file lines.',
            'Old fingerprint-only baseline cannot reconstruct historical DA identities.',
            'Same-SHA before/after test attribution needs separate measured evidence.',
            'This diagnostic does not edit baseline or change threshold/measurement comparison.',
            'Unknown whole-source/unloaded executable denominator remains unchanged.',
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--reports', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = details(args.root, args.reports)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        for path, data in result['files'].items():
            print(f'DA DETAILS {path}: uncovered={data["uncovered_da_line_ids"]}')
        snapshot = json.dumps(result, separators=(',', ':')).encode()
        print('COVERAGE_DA_DETAILS_GZIP_BASE64=' + base64.b64encode(gzip.compress(snapshot, mtime=0)).decode())
        return 0
    except (OSError, ValueError) as error:
        print(f'DA DETAILS FAILED: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
