#!/usr/bin/env python3
"""REG-4c behavioral gate and isolated safety mutations; no business databases."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LOGS = Path('/tmp/reg4c-verification')
LOGS.mkdir(exist_ok=True)
ENV = {k: v for k, v in os.environ.items() if k.lower() not in
       {'http_proxy', 'https_proxy', 'all_proxy', 'muyon_eval_real'}}
ENV['NO_PROXY'] = 'localhost,127.0.0.1,::1'
TARGET = 'test/inquiry_general_write_tools_test.dart'
TOOLS = 'apps/muyon/lib/platform/inquiry_record_tools.dart'
SHELL = 'packages/inquiry_module/lib/src/app/shell.dart'


def run(root, label, name=None, target=TARGET):
    cmd = ['flutter', 'test', '--no-pub', '--reporter', 'expanded', target]
    if name:
        cmd += ['--plain-name', name]
    result = subprocess.run(cmd, cwd=root / 'apps/muyon', env=ENV,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=240)
    (LOGS / f'{label}.log').write_text(result.stdout)
    return result


def mutation(root, label, relative, before, after, test):
    path = root / relative
    original = path.read_text()
    if original.count(before) != 1:
        raise RuntimeError(f'{label}: expected exactly one mutation site')
    try:
        path.write_text(original.replace(before, after, 1))
        result = run(root, label, test)
        meaningful = ('Expected:' in result.stdout and 'Actual:' in result.stdout
                      and '[E]' in result.stdout and
                      'Failed to load' not in result.stdout)
        if result.returncode == 0 or not meaningful:
            print(result.stdout[-6000:])
            raise RuntimeError(f'{label}: survived or failed before behavior assertion')
        print(f'MUTATION {label}: KILLED by {test}', flush=True)
    finally:
        path.write_text(original)


def main():
    base = run(ROOT, 'green-before')
    if base.returncode != 0:
        print(base.stdout[-15000:])
        raise SystemExit('Baseline behavior gate failed')
    print('REG4C baseline: GREEN', flush=True)
    protocol = run(ROOT, 'host-model-protocol',
                   target='test/assistant_production_model_protocol_test.dart')
    if protocol.returncode != 0:
        print(protocol.stdout[-15000:])
        raise SystemExit('Existing host model protocol gate failed')
    print('REG4C existing host model protocol: GREEN', flush=True)
    # Only the archive copy is mutated. The source checkout and tracked tests
    # stay byte-identical; the final invocation runs the original checkout.
    with tempfile.TemporaryDirectory(prefix='reg4c-mutations-') as directory:
        copy = Path(directory) / 'repo'
        shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns(
            '.git', 'build', '.dart_tool', '.flutter-plugins-dependencies',
            'failures', '__pycache__'))
        subprocess.run(['flutter', 'pub', 'get', '--offline'], cwd=copy,
                       env=ENV, check=True, stdout=subprocess.DEVNULL)
        mutation(copy, 'a-version', TOOLS,
                 'if (previous.version != p[\'expected_version\']) {',
                 'if (false) {',
                 'explicit expected_version refuses a stale update even with fresh scope')
        mutation(copy, 'b-protected', TOOLS,
                 '!_protectedFields.contains(field.name)', 'true',
                 'type-specific fields and protected fields fail before approval')
        mutation(copy, 'c-quotation-price', TOOLS,
                 "'quoted_on',", "'price', 'quoted_on',",
                 'quotation schema rejects all pricing and award fields')
        mutation(copy, 'd-hosted-entry', SHELL,
                 'if (!hosted) item(Section.ask),', 'item(Section.ask),',
                 'hosted Folio has no sidebar, palette or shortcut assistant route')
        mutation(copy, 'e-confirmation', TOOLS,
                 'effect: ToolEffect.write,', 'effect: ToolEffect.read,',
                 'unapproved generic write never changes the Store or writes a receipt')
    final = run(ROOT, 'green-after')
    if final.returncode != 0:
        print(final.stdout[-6000:])
        raise SystemExit('Restored original behavior gate failed')
    print('REG4C SUMMARY: GREEN; 5/5 safety mutations killed; restored source GREEN')


if __name__ == '__main__':
    main()
