import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile

from tools.document_fidelity.tests.test_harness import parts, write_zip, REL
from tools.document_fidelity import harness
from tools.document_fidelity.generate_fixtures import build_samples

with tempfile.TemporaryDirectory(prefix='document-review-probes-', dir='/tmp') as tmp:
    root = Path(tmp)
    cases = {}
    p = parts()
    p['[Content_Types].xml'] = p['[Content_Types].xml'].replace(b'</Types>', b'<Default Extension="unused" ContentType=""/></Types>')
    cases['empty-unused-content-type'] = p
    p = parts()
    p['word/_rels/document.xml.rels'] = f'<Relationships xmlns="{REL}"><Relationship Id="r1" Target="document.xml"/></Relationships>'.encode()
    cases['missing-relationship-Type'] = p
    p = parts()
    p['[Content_Types].xml'] = p['[Content_Types].xml'].replace(b'application/vnd.openxmlformats-package.relationships+xml', b'application/octet-stream')
    cases['wrong-rels-content-type'] = p
    p = parts()
    p['xl/workbook.xml'] = b'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>'
    p['[Content_Types].xml'] = p['[Content_Types].xml'].replace(b'</Types>', b'<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml"/></Types>')
    cases['additional-unsupported-main-type'] = p
    for label, members in cases.items():
        path = write_zip(root / (label + '.docx'), members)
        r = harness.inspect(path)
        print(label, json.dumps({'decision': r['decision'], 'structure': r['dimensions']['structure']['status'], 'findings': r['findings']}))

    path = write_zip(root / 'local-encrypted.docx', parts())
    data = bytearray(path.read_bytes())
    struct.pack_into('<H', data, 6, struct.unpack_from('<H', data, 6)[0] | 1)
    path.write_bytes(data)
    r = harness.inspect(path)
    print('local-encrypted', r['decision'], r['findings'])

    path = write_zip(root / 'bad-deflate.docx', parts())
    data = bytearray(path.read_bytes())
    name_length, extra_length = struct.unpack_from('<HH', data, 26)
    offset = 30 + name_length + extra_length
    data[offset:offset + 3] = b'\x06\xff\xff'
    path.write_bytes(data)
    run = subprocess.run([sys.executable, '-m', 'tools.document_fidelity.harness', str(path)], capture_output=True, text=True)
    print('bad-deflate-cli', run.returncode, 'stdout=', repr(run.stdout), 'last-stderr=', run.stderr.splitlines()[-1])

    path = write_zip(root / 'forged-count.docx', {**parts(), **{f'custom/{i}.bin': b'x' for i in range(2050)}})
    data = bytearray(path.read_bytes())
    eocd = data.rfind(b'PK\x05\x06')
    struct.pack_into('<HH', data, eocd + 8, 1, 1)
    path.write_bytes(data)
    original_zipfile = harness.zipfile.ZipFile
    allocated = []
    class RecordingZipFile(original_zipfile):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            allocated.append(len(self.filelist))
    harness.zipfile.ZipFile = RecordingZipFile
    try:
        r = harness.inspect(path)
    finally:
        harness.zipfile.ZipFile = original_zipfile
    print('forged-count', 'bytes=', len(data), 'max_members=', r['limits']['max_members'], 'allocated-entries=', allocated, 'decision=', r['decision'], 'findings=', r['findings'])

    path = root / 'input.docx'
    os.mkfifo(path)
    try:
        run = subprocess.run([sys.executable, '-m', 'tools.document_fidelity.harness', str(path)], capture_output=True, text=True, timeout=1)
        print('fifo-cli', run.returncode, repr(run.stdout))
    except subprocess.TimeoutExpired:
        print('fifo-cli TIMEOUT after 1 second; process killed; regular-file rejection never reached')

    fixtures = Path('tools/document_fidelity/fixtures')
    manifest = json.loads((fixtures / 'manifest.json').read_text())
    samples = build_samples()
    for name, generated in samples.items():
        actual = (fixtures / name).read_bytes()
        print('fixture', name, 'generator-byte-identical=', generated == actual, 'manifest-inspect-identical=', manifest[name] == harness.inspect(fixtures / name), 'sha256=', hashlib.sha256(actual).hexdigest())

    missing = subprocess.run([sys.executable, '-m', 'tools.document_fidelity.harness', str(root / 'missing.docx')], capture_output=True, text=True)
    print('missing-file-cli', missing.returncode, json.loads(missing.stdout)['findings'], 'stderr=', repr(missing.stderr))
