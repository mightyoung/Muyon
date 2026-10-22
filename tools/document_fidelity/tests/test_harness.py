"""Original synthetic specimens, no user documents or external engines."""
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

from tools.document_fidelity.harness import inspect, compare

CT = 'http://schemas.openxmlformats.org/package/2006/content-types'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
OFFICE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
SPECS = {
 'docx': ('word/document.xml', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main', 'document'),
 'xlsx': ('xl/workbook.xml', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main', 'workbook'),
 'pptx': ('ppt/presentation.xml', 'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml', 'http://schemas.openxmlformats.org/presentationml/2006/main', 'presentation'),
}

def parts(kind='docx'):
    main, mime, ns, root = SPECS[kind]
    return {'[Content_Types].xml': f'<Types xmlns="{CT}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="bin" ContentType="application/octet-stream"/><Override PartName="/{main}" ContentType="{mime}"/></Types>'.encode(),
            '_rels/.rels': f'<Relationships xmlns="{REL}"><Relationship Id="rId1" Type="{OFFICE}/officeDocument" Target="{main}"/></Relationships>'.encode(),
            main: f'<{root} xmlns="{ns}"/>'.encode(), 'custom/original.bin': b'Muyon original opaque extension\x00'}

def write_zip(path, members):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, value in members.items():
            entry = zipfile.ZipInfo(name, (2026, 10, 22, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, value)
    return path

class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def sample(self, kind='docx', members=None, name=None):
        return write_zip(self.dir / (name or 'source.' + kind), parts(kind) if members is None else members)

    def reject(self, p, code):
        r = inspect(p)
        self.assertEqual('reject', r['decision'], r)
        self.assertIn(code, [x['code'] for x in r['findings']], r)
        return r

    def test_three_formats_and_honest_dimensions(self):
        for kind in SPECS:
            with self.subTest(kind=kind):
                p = self.sample(kind)
                before = p.read_bytes()
                r = inspect(p)
                self.assertEqual(kind, r['format'])
                self.assertEqual('pass', r['dimensions']['structure']['status'])
                self.assertEqual('unknown', r['fidelity'])
                for d in ('visual', 'formula', 'annotation', 'render', 'recalc'):
                    self.assertEqual('not_run', r['dimensions'][d]['status'])
                self.assertEqual(hashlib.sha256(before).hexdigest(), r['sha256'])
                self.assertEqual(before, p.read_bytes())
                self.assertEqual(set(parts(kind)), {x['name'] for x in r['parts']})

    def test_masquerade(self):
        self.reject(self.sample('xlsx', name='fake.docx'), 'extension_mismatch')

    def test_wrong_content_type_and_root(self):
        p = parts()
        p['[Content_Types].xml'] = p['[Content_Types].xml'].replace(b'document.main+xml', b'template.main+xml')
        self.reject(self.sample(members=p), 'unsupported_main_type')
        p = parts(); p['word/document.xml'] = b'<fake/>'
        self.reject(self.sample(members=p), 'main_root_mismatch')

    def test_missing_main_and_root_relationship(self):
        p = parts(); del p['word/document.xml']
        self.reject(self.sample(members=p), 'missing_main')
        p = parts(); del p['_rels/.rels']
        self.reject(self.sample(members=p), 'missing_package_metadata')

    def test_unsafe_archive_paths(self):
        for name in ('../escape', '/absolute', 'C:/drive', 'a\\b', 'a/../b', 'a/%2e%2e/b'):
            with self.subTest(name=name):
                p = parts(); p[name] = b'x'
                self.reject(self.sample(members=p), 'unsafe_path')

    def test_macro_external_and_embedded_recorded(self):
        for name, data, code in [('word/vbaProject.bin', b'not executable', 'macro'), ('word/embeddings/oleObject1.bin', b'original', 'embedded_object'), ('word/_rels/document.xml.rels', f'<Relationships xmlns="{REL}"><Relationship Id="r1" Type="{OFFICE}/hyperlink" Target="https://invalid.example/never-fetch" TargetMode="External"/></Relationships>'.encode(), 'external_relationship')]:
            with self.subTest(code=code):
                p = parts(); p[name] = data
                self.reject(self.sample(members=p), code)

    def test_xml_entities_utf16_and_malformed(self):
        for data in (b'<!DOCTYPE a [<!ENTITY b "x">]><a>&b;</a>', '<!DOCTYPE a [<!ENTITY b "x">]><a>&b;</a>'.encode('utf-16'), b'<broken'):
            p = parts(); p['custom/evil.xml'] = data
            self.reject(self.sample(members=p), 'unsafe_or_invalid_xml')

    def test_zip_bomb_ratio_and_member_limit(self):
        p = parts(); p['bomb.bin'] = b'0' * 2000000
        self.reject(self.sample(members=p), 'archive_limits')
        p = self.sample()
        r = inspect(p, limits={'max_members': 2})
        self.assertIn('archive_limits', [x['code'] for x in r['findings']])

    def test_duplicate_symlink_and_encryption(self):
        p = self.sample()
        with zipfile.ZipFile(p, 'a') as z:
            entry = zipfile.ZipInfo('custom/link'); entry.create_system = 3; entry.external_attr = 0o120777 << 16
            z.writestr(entry, b'../../escape')
        self.reject(p, 'symlink')
        p = self.sample(); data = bytearray(p.read_bytes())
        pos = data.index(b'PK\x01\x02')
        flags = struct.unpack_from('<H', data, pos + 8)[0]
        struct.pack_into('<H', data, pos + 8, flags | 1)
        p.write_bytes(data)
        self.reject(p, 'encrypted')

    def test_invalid_archive_and_plaintext_not_ooxml(self):
        p = self.dir / 'invalid.docx'; p.write_bytes(b'PK\x03\x04garbage')
        self.reject(p, 'invalid_zip')
        p.write_bytes(b'hello'); self.reject(p, 'unsupported_container')

    def test_compare_unknown_loss_and_changes_fail(self):
        a = self.sample(); before = a.read_bytes(); p = parts(); del p['custom/original.bin']
        b = self.sample(members=p, name='candidate.docx')
        r = compare(a, b)
        self.assertEqual('fail', r['preservation']['status'])
        self.assertEqual(['custom/original.bin'], r['preservation']['missing'])
        p = parts(); p['custom/original.bin'] = b'changed'
        self.sample(members=p, name='candidate.docx')
        self.assertEqual('fail', compare(a, b)['preservation']['status'])
        self.assertEqual(before, a.read_bytes())
        self.assertEqual('pass', compare(a, a)['preservation']['status'])
        self.assertEqual('unknown', compare(a, a)['fidelity'])

    def test_pdf_preflight_never_certifies_safety(self):
        p = self.dir / 'sample.pdf'; p.write_bytes(b'%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\n%%EOF\n')
        r = inspect(p)
        self.assertEqual('pdf', r['format'])
        self.assertEqual('quarantine', r['decision'])
        self.assertEqual('not_run', r['dimensions']['structure']['status'])
        self.assertEqual('unknown', r['safety'])
        p.write_bytes(b'%PDF-1.4\n/JavaScript /Encrypt /EmbeddedFile\n%%EOF')
        self.reject(p, 'pdf_risk_marker')
        p.write_bytes(b'%PDF-1.4'); self.reject(p, 'pdf_incomplete')

    def test_cli_stdout_and_original_untouched(self):
        p = self.sample(); before = p.read_bytes()
        r = subprocess.run([sys.executable, '-m', 'tools.document_fidelity.harness', str(p)], capture_output=True, text=True)
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertEqual('docx', json.loads(r.stdout)['format'])
        self.assertEqual(before, p.read_bytes())


class AdditionalBoundaryTests(unittest.TestCase):
    setUp = HarnessTests.setUp
    sample = HarnessTests.sample
    reject = HarnessTests.reject
    def test_relationship_escape_and_missing_target(self):
        for target in ('../../../escape', 'missing.xml'):
            p = parts()
            p['word/_rels/document.xml.rels'] = f'<Relationships xmlns="{REL}"><Relationship Id="r1" Type="{OFFICE}/image" Target="{target}"/></Relationships>'.encode()
            self.reject(self.sample(members=p), 'invalid_relationship_target')

    def test_duplicate_and_crc_corruption(self):
        import warnings
        p = self.sample()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(p, 'a') as z:
                z.writestr('custom/original.bin', b'duplicate')
        self.reject(p, 'duplicate_part')
        p = self.sample(); data = bytearray(p.read_bytes())
        pos = data.index(b'PK\x01\x02')
        data[pos + 16] ^= 0xff
        p.write_bytes(data)
        self.reject(p, 'invalid_zip')

    def test_local_header_encryption_and_flags_disagreement(self):
        for flag, code in ((1, 'encrypted'), (8, 'invalid_zip')):
            with self.subTest(flag=flag):
                p = self.sample(); data = bytearray(p.read_bytes())
                struct.pack_into('<H', data, 6, struct.unpack_from('<H', data, 6)[0] | flag)
                p.write_bytes(data)
                self.reject(p, code)

    def test_relationship_type_and_declared_mime_required(self):
        members = parts()
        members['word/_rels/document.xml.rels'] = f'<Relationships xmlns="{REL}"><Relationship Id="r2" Target="document.xml"/></Relationships>'.encode()
        self.reject(self.sample(members=members), 'invalid_relationships')

    def test_relationship_declared_mime_required(self):
        members = parts()
        members['[Content_Types].xml'] = members['[Content_Types].xml'].replace(b'application/vnd.openxmlformats-package.relationships+xml', b'application/xml')
        self.reject(self.sample(members=members), 'invalid_relationship_content_type')

    def test_unused_content_type_cannot_be_empty(self):
        members = parts()
        members['[Content_Types].xml'] = members['[Content_Types].xml'].replace(b'</Types>', b'<Default Extension="unused" ContentType=""/></Types>')
        self.reject(self.sample(members=members), 'invalid_content_types')

    def test_corrupt_deflate_is_structured_rejection(self):
        p = self.sample()
        data = bytearray(p.read_bytes())
        with zipfile.ZipFile(p) as z:
            info = z.infolist()[0]
            offset = info.header_offset
            namelen, extra = struct.unpack_from('<HH', data, offset + 26)
            data[offset + 30 + namelen + extra] = 0x07  # invalid deflate block type
        p.write_bytes(data)
        self.reject(p, 'invalid_zip')

    def test_limits_and_deep_xml(self):
        p = self.sample()
        self.assertEqual('reject', inspect(p, {'max_file': 10})['decision'])
        self.assertEqual('reject', inspect(p, {'max_total': 10})['decision'])
        self.assertEqual('reject', inspect(p, {'max_member': 10})['decision'])
        members = parts(); members['custom/deep.xml'] = b'<a>' * 140 + b'</a>' * 140
        self.reject(self.sample(members=members), 'unsafe_or_invalid_xml')
        with self.assertRaises(ValueError):
            inspect(p, {'max_file': 1000000000})

    def test_active_formulas_and_cfb(self):
        p = parts('xlsx'); p['xl/worksheets/sheet1.xml'] = f'<worksheet xmlns="{SPECS["xlsx"][2]}"><sheetData><row><c><f>WEBSERVICE("https://invalid.example")</f></c></row></sheetData></worksheet>'.encode()
        self.reject(self.sample('xlsx', members=p), 'active_field_or_formula')
        p = self.dir / 'encrypted.docx'; p.write_bytes(bytes.fromhex('d0cf11e0a1b11ae1') + b'original synthetic')
        self.reject(p, 'encrypted_or_legacy_container')

    def test_pdf_obfuscated_names(self):
        p = self.dir / 'obfuscated.pdf'; p.write_bytes(b'%PDF-1.7\n/Java#53cript\n%%EOF')
        self.reject(p, 'pdf_risk_marker')

    def test_fixture_generation_reproducible_and_usable(self):
        from tools.document_fidelity.generate_fixtures import build_samples
        one, two = build_samples(), build_samples()
        self.assertEqual({'minimal.docx', 'minimal.xlsx', 'minimal.pptx', 'minimal.pdf'}, set(one))
        self.assertEqual(one, two)
        for name, data in one.items():
            p = self.dir / name; p.write_bytes(data)
            r = inspect(p)
            self.assertNotEqual('reject', r['decision'], r)
            self.assertEqual(hashlib.sha256(data).hexdigest(), r['sha256'])
        self.assertIn(b'startxref', one['minimal.pdf'])
        for name in ('minimal.xlsx', 'minimal.pptx'):
            with zipfile.ZipFile(self.dir / name) as z:
                self.assertTrue(any('sheet1.xml' in x or 'slide1.xml' in x for x in z.namelist()))

if __name__ == '__main__':
    unittest.main()
