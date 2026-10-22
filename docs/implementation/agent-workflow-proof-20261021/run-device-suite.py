import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

repo = Path('/private/tmp/muyon-android-refactor-20261020')
sys.path.insert(0, str(repo / 'apps/muyon_android/checks'))
from instrumentation_gate import evaluate
from suite_gate import check

adb = '/Users/muyi/Library/Android/sdk/platform-tools/adb'
prefix = Path('/private/tmp/muyon-workflow-final4')
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
build_id = Path('/private/tmp/muyon-product-inputs/build-id.txt').read_text().strip()
apk = Path(f'/private/tmp/muyon-workflows-{source[:8]}.apk')
test_apk = Path(f'/private/tmp/muyon-workflows-{source[:8]}-androidTest.apk')
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
manifest = dict(source_commit=source, build_id=build_id, apk=str(apk), test_apk=str(test_apk),
                apk_sha256=digest(apk), test_apk_sha256=digest(test_apk), runs=[])
inventory = []
for file in (repo / 'apps/muyon_android/app/src/androidTest').rglob('*Test.kt'):
    content = file.read_text()
    package = re.search(r'^package ([\w.]+)', content, re.M).group(1)
    name = re.search(r'^class (\w+)', content, re.M).group(1)
    inventory.extend(f'{package}.{name}#{method}' for method in re.findall(r'@Test\s+fun (\w+)\(', content))
picker_class = 'com.mightyoung.muyon.product.SystemPickerProductTest'

def command(*args):
    subprocess.run([adb, '-s', 'emulator-5556', *args], check=True, stdout=subprocess.DEVNULL)

def run(label, required):
    log = Path(f'{prefix}-{label}.log')
    with log.open('w') as stream:
        result = subprocess.run([adb, '-s', 'emulator-5556', 'shell', 'am', 'instrument', '-w', '-r',
            '-e', 'class', ','.join(required), '-e', 'muyon_source', build_id,
            'com.mightyoung.muyon.product.test/androidx.test.runner.AndroidJUnitRunner'], stdout=stream, stderr=subprocess.STDOUT)
    gate = evaluate(log.read_text(), result.returncode, set(required))
    if gate['gate'] != 'PASS':
        print(json.dumps(gate), flush=True)
        raise SystemExit(1)
    manifest['runs'].append(dict(log=str(log), log_sha256=digest(log), adb_exit=result.returncode,
        required=required, build_id=build_id, apk_sha256=manifest['apk_sha256'], test_apk_sha256=manifest['test_apk_sha256']))
    print(f'{label}: {len(required)} PASS', flush=True)

run('nonpicker', sorted(x for x in inventory if not x.startswith(picker_class + '#')))
run('GENERATE', [picker_class + '#generatePickerInputs'])
command('shell', 'mkdir', '-p', '/sdcard/Download/MuyonRefactorFixtures')
command('shell', 'cp', '-R', '/sdcard/Android/data/com.mightyoung.muyon.product/files/picker-fixtures/.', '/sdcard/Download/MuyonRefactorFixtures/')
run('PDF', [picker_class + '#pdfSystemPickerManualReviewAndPrivateAttachment'])
run('ZIP', [picker_class + '#zipSystemPickerReviewAndImport'])
run('DIRECTORY', [picker_class + '#directorySystemPickerReviewAndImport'])
command('shell', 'rm', '/sdcard/Download/MuyonRefactorFixtures/picker-paper.pdf')
run('PRIVATE', [picker_class + '#reopenPrivatePdfAfterOriginalRemoved'])
output = repo / 'docs/implementation/agent-workflow-proof-20261021'
output.mkdir(exist_ok=True)
(output / 'suite-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
gate = check(manifest, repo / 'apps/muyon_android/app/src/androidTest')
(output / 'suite-gate.json').write_text(json.dumps(gate, indent=2) + '\n')
print(json.dumps(gate), flush=True)
