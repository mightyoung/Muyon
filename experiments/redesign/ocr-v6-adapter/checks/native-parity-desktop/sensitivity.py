"""Prove numerical and text gates reject corruption; restore raw artifacts."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import numpy as np
from run import ROOT, compare

base = Path('/tmp/ocr-native-parity')
assets = Path('/workspace/ocr-assets')
results = {}
with tempfile.TemporaryDirectory(prefix='ocr-parity-gate-') as tmp:
    report = Path(tmp)/'mutated.json'
    tests = [('tensor',base/'4.12.0/tiny/english/det-input.npy'),('text',base/'4.12.0/tiny/english/result.json'),('missingStage',base/'4.12.0/tiny/english/rec-output-0.npy')]
    for label, path in tests:
        original = path.read_bytes()
        try:
            if label == 'tensor':
                x = np.load(path); x.flat[0] += .1; np.save(path,x)
            elif label == 'text':
                x = json.loads(path.read_text()); x['text'][0] += ' CORRUPT'; path.write_text(json.dumps(x))
            else:
                path.unlink()
            with contextlib.redirect_stdout(io.StringIO()):
                status = compare(base,report,assets)
            rejected = status == 1 and not json.loads(report.read_text())['desktopDiagnosticPassed']
            assert rejected, label
            results[label] = dict(injected=True,rejected=True)
        finally:
            path.write_bytes(original)
    with contextlib.redirect_stdout(io.StringIO()):
        status = compare(base,ROOT/'evidence/parity-desktop.json',assets)
    assert status == 0
results['restoredComparisonPassed'] = True
(ROOT/'evidence/parity-sensitivity.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results))
