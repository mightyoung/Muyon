import hashlib
import json
from pathlib import Path
import sys

from tools.document_fidelity.generate_fixtures import build_samples
from tools.document_fidelity.complex_fixtures import build_complex_samples, operation_contract
from tools.document_fidelity.harness import inspect
from tools.document_fidelity.engine_inventory import collect

root = Path('tools/document_fidelity')
before = {}
for directory, generated in [('fixtures', build_samples()), ('fixtures_complex', build_complex_samples())]:
    manifest = json.loads((root / directory / 'manifest.json').read_text())
    for name, payload in generated.items():
        path = root / directory / name
        actual = path.read_bytes()
        before[str(path)] = hashlib.sha256(actual).hexdigest()
        assert actual == payload, name
        assert payload == (build_samples() if directory == 'fixtures' else build_complex_samples())[name]
        report = inspect(path)
        if directory == 'fixtures':
            assert manifest[name] == report, name
        else:
            contract = operation_contract(name, report)
            assert manifest[name] == dict(source=report, operation_contract=contract), name
            assert contract['execution_allowed'] is False
            assert all(contract[field] == 'not_run' for field in ('round_trip', 'independent_reopen', 'semantic_comparison', 'render', 'recalc', 'visual', 'annotation'))
            assert set(contract['byte_invariant_parts']) == {part['name'] for part in report['parts']} - set(contract['allowed_changed_parts'])
            assert 'custom/original.bin' in contract['byte_invariant_parts']
        print(name, 'deterministic/committed-bytes/manifest: PASS', report['sha256'])

fresh = collect()
recorded = json.loads(Path('docs/tasks/document-fidelity-harness-20261022/engine-evaluation/evidence/installed-inventory.json').read_text())
assert fresh == recorded, 'live metadata differs from committed evidence'
print('Fresh metadata inventory exactly matches committed inventory: PASS')
assert fresh['engine_execution'] == 'not_run'
assert fresh['integration_approved'] is False
assert fresh['isolation_proven'] is False
assert fresh['libreoffice']['executed'] is False
for name in ('docx', 'pptx', 'openpyxl', 'lxml', 'PIL', 'xlsxwriter', 'et_xmlfile'):
    assert name not in sys.modules, name
print('No document-engine modules imported; no engine or namespace subprocess invoked by this script: PASS')
for name, digest in before.items():
    assert hashlib.sha256(Path(name).read_bytes()).hexdigest() == digest
print('All six source fixtures remain byte-identical after inspection: PASS')
