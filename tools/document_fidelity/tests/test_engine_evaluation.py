"""Metadata and original synthetic fixtures; no engine imports/execution."""
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET

from tools.document_fidelity.harness import inspect
from tools.document_fidelity import engine_inventory, complex_fixtures

class InventoryTests(unittest.TestCase):
    def test_installed_metadata_or_explicit_absence(self):
        r = engine_inventory.collect()
        self.assertIn('engine_execution', r)
        self.assertEqual('not_run', r['engine_execution'])
        self.assertFalse(r['integration_approved'])
        self.assertEqual({'python-docx','python-pptx','openpyxl','lxml','et_xmlfile','typing_extensions','Pillow','XlsxWriter'}, set(r['distributions']))
        for value in r['distributions'].values():
            self.assertIn(value['status'], ('installed_metadata_only', 'not_installed'))
            if value['status'] == 'installed_metadata_only':
                self.assertTrue(value['version'])
                self.assertIsInstance(value['requires_dist'], list)
                self.assertIn('METADATA', [Path(x['relative_path']).name for x in value['evidence']])
                for item in value['evidence']:
                    self.assertEqual(64, len(item['sha256']))
        self.assertIn('origin_authenticity_not_verified', r['limitations'])

    def test_local_license_hash_and_missing_origin(self):
        from importlib import metadata
        try:
            d = metadata.distribution('python-docx')
        except metadata.PackageNotFoundError:
            self.skipTest('optional existing distribution absent')
        value=engine_inventory.distribution_record('python-docx')
        self.assertIn('evidence', value)
        licenses=[x for x in value['evidence'] if 'license' in x['relative_path'].lower()]
        self.assertTrue(licenses)
        for item in licenses:
            path=Path(d.locate_file(item['relative_path']))
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), item['sha256'])
        self.assertIn('wheel_archive_or_index_origin_unverified', value['gaps'])

class ComplexFixtureTests(unittest.TestCase):
    def test_two_deterministic_packages_and_operation_contracts(self):
        samples = complex_fixtures.build_complex_samples()
        self.assertEqual({'complex.docx','complex.xlsx'}, set(samples))
        self.assertEqual(samples, complex_fixtures.build_complex_samples())
        with tempfile.TemporaryDirectory() as tmp:
            for name, payload in samples.items():
                p=Path(tmp)/name; p.write_bytes(payload); before=p.read_bytes()
                r=inspect(p)
                self.assertEqual('inspect_only', r['decision'], r)
                self.assertEqual(hashlib.sha256(payload).hexdigest(), r['sha256'])
                self.assertEqual(before,p.read_bytes())
                contract=complex_fixtures.operation_contract(name, r)
                self.assertEqual('not_run', contract['round_trip'])
                self.assertEqual(r['sha256'],contract['source_sha256'])
                self.assertEqual('not_run',contract['independent_reopen'])
                self.assertEqual(1,len(contract['allowed_changed_parts']))
                self.assertIn('custom/original.bin',contract['byte_invariant_parts'])
                self.assertFalse(contract['execution_allowed'])

    def test_docx_split_runs_comment_bookmark_header(self):
        samples=complex_fixtures.build_complex_samples()
        self.assertIn('complex.docx', samples)
        data=samples['complex.docx']
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            root=ET.fromstring(z.read('word/document.xml'))
            ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
            self.assertEqual(['Original ', 'target', ' unchanged'],[x.text for x in root.findall('.//w:t',ns)])
            self.assertTrue(root.findall('.//w:b',ns))
            self.assertTrue(root.findall('.//w:bookmarkStart',ns))
            self.assertIn('word/comments.xml',z.namelist())
            self.assertIn('word/header1.xml',z.namelist())

    def test_xlsx_stale_formula_cache_and_hidden_date_merge_comment(self):
        samples=complex_fixtures.build_complex_samples()
        self.assertIn('complex.xlsx', samples)
        data=samples['complex.xlsx']
        ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            root=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
            cells={x.get('r'):x for x in root.findall('.//s:c',ns)}
            self.assertEqual('2',cells['A1'].find('s:v',ns).text)
            self.assertEqual('A1+1',cells['B1'].find('s:f',ns).text)
            self.assertEqual('999',cells['B1'].find('s:v',ns).text) # deliberate stale cache
            self.assertEqual('A3:B3',root.find('s:mergeCells/s:mergeCell',ns).get('ref'))
            workbook=ET.fromstring(z.read('xl/workbook.xml'))
            self.assertEqual('1',workbook.find('s:workbookPr',ns).get('date1904'))
            self.assertTrue(any(x.get('state')=='hidden' for x in workbook.findall('s:sheets/s:sheet',ns)))
            self.assertEqual('Original!$A$1',workbook.find('s:definedNames/s:definedName',ns).text)
            self.assertIn('xl/comments/comment1.xml',z.namelist())
            self.assertIn('custom/original.bin',z.namelist())

if __name__ == '__main__':
    unittest.main()
