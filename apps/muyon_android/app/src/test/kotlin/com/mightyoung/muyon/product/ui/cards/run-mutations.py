#!/usr/bin/env python3
"""Compile temporary card mutants, require runtime assertion failures; no host calls."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import os
import subprocess
import tempfile

root = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip())
source = root / 'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/cards/CardModels.kt'
test = root / 'apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/CardProjectionChecks.kt'
compiler = os.environ.get('KOTLINC', 'kotlinc')
base = source.read_text()
mutations = {
    'unknown-cancellable': ('status == ReceiptStatus.Running && !cancelRequested', '(status == ReceiptStatus.Running || status == ReceiptStatus.Unknown) && !cancelRequested'),
    'unknown-draft-editable': ('saveStatus != DraftSaveStatus.Saving && saveStatus != DraftSaveStatus.Unknown', 'saveStatus != DraftSaveStatus.Saving'),
    'conflict-can-save': ('ReportVersionStatus.Conflict -> setOf(CardCapability.ViewVersion, CardCapability.CompareVersions)', 'ReportVersionStatus.Conflict -> setOf(CardCapability.ViewVersion, CardCapability.CompareVersions, CardCapability.PreviewReportSave)'),
}
print('Fresh rerun; NOT an earlier original log', flush=True)
print('UTC: ' + datetime.now(timezone.utc).isoformat(), flush=True)
print('Source HEAD: ' + subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(), flush=True)
print('CardModels SHA256: ' + hashlib.sha256(source.read_bytes()).hexdigest(), flush=True)
print('Checks SHA256: ' + hashlib.sha256(test.read_bytes()).hexdigest(), flush=True)
for name, (old, new) in mutations.items():
    assert base.count(old) == 1, name + ': replacement must match once'
    with tempfile.TemporaryDirectory(prefix='cards-mutation-') as folder:
        src = Path(folder) / 'CardModels.kt'
        jar = Path(folder) / 'checks.jar'
        src.write_text(base.replace(old, new))
        command = [compiler, '-Werror', '-jvm-target', '17', str(src), str(test), '-include-runtime', '-d', str(jar)]
        result = subprocess.run(command, text=True, capture_output=True)
        print(name + ' compile exit: ' + str(result.returncode), flush=True)
        print(result.stdout + result.stderr, end='', flush=True)
        assert result.returncode == 0, name + ': compilation failure is not a killed mutant'
        result = subprocess.run(['java', '-jar', str(jar)], text=True, capture_output=True)
        print(name + ' runtime exit: ' + str(result.returncode), flush=True)
        print(result.stdout + result.stderr, end='', flush=True)
        assert result.returncode != 0 and 'IllegalStateException: Check failed' in result.stderr, name + ': expected assertion failure'
        print(name + ': KILLED (runtime assertion)', flush=True)
print('PASS: 3/3 safety mutants killed', flush=True)
