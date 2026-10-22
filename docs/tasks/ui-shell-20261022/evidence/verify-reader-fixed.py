#!/usr/bin/env python3
"""Compile immutable real reader sources. No production files/stubs or Android execution."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
COMPILER = Path('/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc')
FIXED = '8d2b7931fa6b9194338ec81f1add8110075b92bc'
BEFORE = '3d2be1e783652735b79e9b58f6461d88ce131dc4'
PREFIX = 'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/documents/'
CHECKS = 'apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents/DocumentReaderChecks.kt'


def source(commit, path):
    return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=ROOT)


runs = []
for name, model_sha, parser_sha, skip_inline, expected in [
    ('reader-fixed-all-green', FIXED, FIXED, False, 0),
    ('reader-inline-phonetic-red', FIXED, BEFORE, False, 1),
    ('reader-shared-phonetic-red', FIXED, BEFORE, True, 1),
    ('reader-highlight-empty-red', BEFORE, FIXED, False, 1),
]:
    with tempfile.TemporaryDirectory(prefix='muyon-reader-fixed-') as temp:
        folder = Path(temp)
        payloads = {
            'DocumentReaderModels.kt': source(model_sha, PREFIX + 'DocumentReaderModels.kt'),
            'OfficeTextPreview.kt': source(parser_sha, PREFIX + 'OfficeTextPreview.kt'),
            'DocumentReaderChecks.kt': source(FIXED, CHECKS),
        }
        if skip_inline:
            # Let the identical later sharedStrings assertion execute after the known inline failure.
            # No production source changes; exact diff is recorded in the log and manifest.
            old = '    check(inlinePhonetic.single().text == "A1: 東京駅\\nB1: next\\n") { inlinePhonetic.single().text }'
            text = payloads['DocumentReaderChecks.kt'].decode()
            assert text.count(old) == 1
            text = text.replace(old, '    println("isolated sharedStrings probe: preceding inline actual=" + inlinePhonetic.single().text)')
            payloads['DocumentReaderChecks.kt'] = text.encode()
        identities = {}
        for filename, raw in payloads.items():
            (folder / filename).write_bytes(raw)
            identities[filename] = hashlib.sha256(raw).hexdigest()
        command = [str(COMPILER), '-Werror', '-jvm-target', '17']
        command += [str(folder / name) for name in payloads]
        command += ['-include-runtime', '-d', str(folder / 'checks.jar')]
        compile_run = subprocess.run(command, capture_output=True, text=True)
        output = 'command=' + json.dumps(command) + '\n'
        output += 'sources=' + json.dumps(identities) + '\n'
        output += f'models_commit={model_sha}\nparser_commit={parser_sha}\nchecks_commit={FIXED}\n'
        output += f'isolated_shared_probe={skip_inline}\ncompile_exit={compile_run.returncode}\n'
        output += compile_run.stdout + compile_run.stderr
        runtime_code = None
        if compile_run.returncode == 0:
            run = subprocess.run(['java', '-jar', str(folder / 'checks.jar')], capture_output=True, text=True)
            runtime_code = run.returncode
            output += f'runner_exit={runtime_code}\n' + run.stdout + run.stderr
        (OUT / f'{name}.log').write_text(output)
        result = dict(name=name, models_commit=model_sha, parser_commit=parser_sha, checks_commit=FIXED,
                      isolated_shared_probe=skip_inline, sha256=identities, compile_exit=compile_run.returncode,
                      runner_exit=runtime_code, expected_runner_exit=expected)
        runs.append(result)
        print(json.dumps(result), flush=True)
(OUT / 'reader-fixed-results.json').write_text(json.dumps(runs, indent=2) + '\n')
assert all(x['compile_exit'] == 0 and x['runner_exit'] == x['expected_runner_exit'] for x in runs)
