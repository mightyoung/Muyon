#!/usr/bin/env python3
"""Loaded executable-line coverage, not a whole-source coverage estimate."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

VERSION = 1
PACKAGES = ['packages/muyon_module_api', 'packages/muyon_ui',
            'packages/prototype_module', 'packages/research_module',
            'packages/supplier_core', 'packages/inquiry_module',
            'apps/muyon', 'apps/muyon_ui_preview']
SUITES = ['module_api', 'muyon_ui', 'prototype', 'research',
          'supplier_core', 'host', 'ui_preview', 'inquiry']
WORKING_DIRS = dict(zip(SUITES, [*PACKAGES[:5], 'apps/muyon',
                               'apps/muyon_ui_preview', 'apps/muyon']))
GATE_PREFIXES = ['packages/muyon_module_api/lib/',
                 'apps/muyon/lib/services/models/',
                 'apps/muyon/lib/services/transfer/']


def measure(root, reports):
    lines = {}
    for suite in SUITES:
        report = reports / suite / 'lcov.info'
        if not report.is_file() or not report.stat().st_size:
            raise ValueError(f'missing/empty coverage report: {suite}')
        current = None
        records = 0
        for text in report.read_text().splitlines():
            if text.startswith('SF:'):
                source = Path(text[3:])
                # Flutter resolves SF relative to the test command working directory.
                working = WORKING_DIRS[suite]
                source = source if source.is_absolute() else root / working / source
                try:
                    current = source.resolve().relative_to(root.resolve()).as_posix()
                except ValueError:
                    current = None  # dependencies outside repository, explicitly excluded
                if current and not any(current.startswith(p + '/lib/') for p in PACKAGES):
                    current = None
                if current and not (root / current).is_file():
                    raise ValueError(f'LCOV source is missing: {current}')
            elif text.startswith('DA:') and current:
                fields = text[3:].split(',')
                number, hits = int(fields[0]), int(fields[1])
                if number <= 0 or hits < 0:
                    raise ValueError('invalid DA record')
                lines.setdefault(current, {})[number] = (
                    lines.get(current, {}).get(number, False) or hits > 0)
                records += 1
        if not records:
            raise ValueError(f'no repository lib executable records: {suite}')
    packages = {}
    for package in PACKAGES:
        sources = sorted(p.relative_to(root).as_posix()
                         for p in (root / package / 'lib').rglob('*.dart'))
        loaded = {p: data for p, data in lines.items() if p.startswith(package + '/lib/')}
        executable = sum(len(data) for data in loaded.values())
        hit = sum(sum(data.values()) for data in loaded.values())
        packages[package] = {
            'loaded_executable_lines': executable, 'hit_lines': hit,
            'loaded_line_percent': round(100 * hit / executable, 4) if executable else None,
            'loaded_files': len(loaded), 'source_files': len(sources),
            'unloaded_source_files': sorted(set(sources) - set(loaded)),
            'unloaded_executable_denominator': 'unknown',
            'whole_package_percent': 'unknown',
        }
    gates = {}
    for prefix in GATE_PREFIXES:
        selected = {p: data for p, data in lines.items() if p.startswith(prefix)}
        inventory = sorted(p.relative_to(root).as_posix()
                           for p in (root / prefix).rglob('*.dart'))
        gates[prefix] = {
            'source_files': inventory,
            'loaded_denominator': {
                p: {'line_count': len(data),
                    'line_set_sha256': hashlib.sha256(
                        ','.join(map(str, sorted(data))).encode()).hexdigest()}
                for p, data in sorted(selected.items())},
            'file_hit_lines': {p: sum(data.values()) for p, data in sorted(selected.items())},
            'loaded_executable_lines': sum(len(data) for data in selected.values()),
            'hit_lines': sum(sum(data.values()) for data in selected.values()),
        }
    return {
        'measurement_version': VERSION,
        'source_sha': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'measurement_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'platform': 'linux', 'flutter_version': '3.47.5',
        'suites': SUITES, 'packages': packages, 'gates': gates,
        'exclusions': ['outside-repository dependencies', 'outside eight lib/ directories'],
        'limitations': [
            'Only DA records are executable denominators; unloaded executable denominator is unknown.',
            'No generated or low-coverage lib source is excluded.',
            'Linux test self-skips include macOS font goldens and external/model/platform restrictions.',
            'Test skip counts and test outcomes are recorded separately in suite-summary.json.',
            'UI behavior tests run in the same eight suites; loaded UI is included.',
            'No whole-repository or whole-package coverage percentage is claimed.',
        ],
    }


def compare(actual, baseline):
    errors = []
    for key in ('measurement_version', 'measurement_sha256', 'platform', 'flutter_version', 'suites', 'exclusions'):
        if actual[key] != baseline[key]:
            errors.append(f'measurement contract changed: {key}; remeasure/review baseline')
    if set(actual['gates']) != set(baseline['gates']):
        errors.append('gate scopes changed')
    for scope, previous in baseline['gates'].items():
        current = actual['gates'].get(scope)
        if not current:
            continue
        if current['source_files'] != previous['source_files'] or current['loaded_denominator'] != previous['loaded_denominator']:
            errors.append(f'denominator drift: {scope}; review/remeasure, never silently accept')
        if not previous['loaded_executable_lines']:
            errors.append(f'empty baseline gate: {scope}')
        for path, hits in previous.get('file_hit_lines', {}).items():
            if current.get('file_hit_lines', {}).get(path, 0) < hits:
                errors.append(f'coverage decrease: {path}')
        if current['hit_lines'] < previous['hit_lines']:
            errors.append(f'coverage decrease: {scope}: {current["hit_lines"]} < {previous["hit_lines"]}')
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--reports', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    try:
        actual = measure(args.root, args.reports)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(actual, indent=2) + '\n')
        for package, data in actual['packages'].items():
            print(f'COVERAGE {package}: {data["hit_lines"]}/{data["loaded_executable_lines"]} loaded executable lines ({data["loaded_line_percent"]}%); unloaded source files={len(data["unloaded_source_files"])}; whole-package=unknown')
        if args.baseline:
            if not args.baseline.is_file():
                raise ValueError('missing baseline')
            errors = compare(actual, json.loads(args.baseline.read_text()))
            if errors:
                raise ValueError('; '.join(errors))
        print('COVERAGE SUMMARY: OK')
        return 0
    except (ValueError, OSError, KeyError) as error:
        print(f'COVERAGE SUMMARY: FAILED: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
