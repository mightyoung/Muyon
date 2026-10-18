"""Fail closed on mutable refs, wrong checkout, dirty tracked or untracked inputs."""
import re
import subprocess
from pathlib import Path


def validate(root, expected):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    if not re.fullmatch('[0-9a-f]{40}', expected):
        raise RuntimeError('exact_40_character_source_sha_required')
    if git('rev-parse', 'HEAD') != expected or git('status', '--porcelain'):
        raise RuntimeError('exact_clean_source_required')
    return dict(source_sha=expected, source_tree=git('rev-parse', 'HEAD^{tree}'))


if __name__ == '__main__':
    import argparse, json
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--source-root', type=Path, default=Path.cwd())
    args = parser.parse_args()
    print(json.dumps(validate(args.source_root, args.expected_source)))
