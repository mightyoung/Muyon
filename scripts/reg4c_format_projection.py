#!/usr/bin/env python3
"""Emit formatted task-owned sources without editing the checkout under test."""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'diff', '--name-only', '7773b7d96bc99f173b57a723d61526fba0df49ff', 'HEAD'], cwd=ROOT, text=True).splitlines()
with tempfile.TemporaryDirectory(prefix='reg4c-format-') as directory:
    for relative in files:
        if not relative.endswith('.dart'):
            continue
        original = ROOT / relative
        copy = Path(directory) / original.name
        copy.write_text(original.read_text())
        subprocess.run(['dart', 'format', str(copy)], check=True, stdout=subprocess.DEVNULL)
        formatted = copy.read_text()
        if formatted != original.read_text():
            print('REG4C_FORMAT ' + json.dumps({'path': relative, 'content': formatted}), flush=True)
