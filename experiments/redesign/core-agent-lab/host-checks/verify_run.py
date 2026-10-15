"""Require terminal Flutter success with no skipped host tests."""
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
if 'All tests passed!' not in text:
    raise SystemExit('missing terminal host-test success')
if re.search(r'\bSKIP(?:PED)?\b|\+[0-9]+\s+~[1-9]', text, re.I):
    raise SystemExit('host tests must not be skipped')
print('HOST SUITE: terminal success; no skips')
