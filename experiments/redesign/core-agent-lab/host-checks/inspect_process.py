"""Shared process evidence oracle used by Dart tests and helper inverses."""
import argparse
import json
from pathlib import Path


def inspect(evidence, expected_launches=1, require_reaped=True):
    evidence = Path(evidence)
    manifest = evidence / 'launches.jsonl'
    assert manifest.is_file(), 'launch_manifest_missing'
    records = [json.loads(line) for line in manifest.read_text().splitlines()]
    assert expected_launches is None or len(records) == expected_launches, 'unexpected_launch_count'
    identities = [record['launch_id'] for record in records]
    assert len(set(identities)) == len(identities), 'duplicate_launch_identity'
    directories = {path.name for path in evidence.glob('launch-*') if path.is_dir()}
    assert directories == set(identities), 'unrecorded_launch_directory'
    for record in records:
        directory = evidence / record['launch_id']
        assert json.loads((directory / 'launch.json').read_text()) == record, 'launch_manifest_mismatch'
        if require_reaped:
            exit_path = directory / 'exit.json'
            assert exit_path.is_file(), 'child_not_reaped'
            assert json.loads(exit_path.read_text())['reaped'] is True, 'child_not_reaped'
            assert not Path('/proc', str(record['pid'])).exists(), 'child_still_alive'
            assert not Path('/proc', str(record['launcher_pid'])).exists(), 'launcher_still_alive'
    return {'launch_count': len(records), 'reaped_count': len(records) if require_reaped else None}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('evidence')
    parser.add_argument('--expected-launches', type=int, default=1)
    parser.add_argument('--allow-running', action='store_true')
    parser.add_argument('--all-launches', action='store_true')
    arguments = parser.parse_args()
    try:
        result = inspect(arguments.evidence, None if arguments.all_launches else arguments.expected_launches,
                         not arguments.allow_running)
    except (AssertionError, KeyError, ValueError, OSError) as error:
        print(str(error) if isinstance(error, AssertionError) else 'invalid_process_evidence')
        return 1
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
