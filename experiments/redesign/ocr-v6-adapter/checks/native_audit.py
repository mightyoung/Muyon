"""Inspect published SDK dependencies; ELF alignment is necessary, not device proof."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

ARTIFACTS = {
    'ort': ('com.microsoft.onnxruntime:onnxruntime-android:1.21.1', '30e594a4b9246fe3ca25768570e90f71e6d33ceb7b7dd72f92dcd7c267611d3f'),
    'opencv': ('com.quickbirdstudios:opencv:4.5.3', 'a07523cb265b26a5d0c4fa01d925ca4855f5a181d70d2f5d99ec47fc4328826a'),
}

def audit(directory):
    rows = []
    manifests = {}
    for name, (coordinate, expected) in ARTIFACTS.items():
        path = directory / (name + '.aar')
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, coordinate
        with zipfile.ZipFile(path) as archive, tempfile.TemporaryDirectory() as tmp:
            manifests[name] = archive.read('AndroidManifest.xml').decode()
            for entry in archive.namelist():
                if not entry.endswith('.so'):
                    continue
                data = archive.read(entry)
                binary = Path(tmp) / 'library.so'
                binary.write_bytes(data)
                output = subprocess.check_output(['readelf', '-lW', str(binary)], text=True)
                alignments = [line.split()[-1] for line in output.splitlines() if line.strip().startswith('LOAD')]
                rows.append(dict(artifact=name, entry=entry, bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                    loadAlignments=alignments, elf16KiBAligned=bool(alignments) and all(int(v,16)>=16384 for v in alignments)))
    return dict(artifacts=ARTIFACTS, manifests=manifests, libraries=rows,
        shippingGate='BLOCKED' if any(not row['elf16KiBAligned'] and ('arm64-v8a' in row['entry'] or 'x86_64' in row['entry']) for row in rows) else 'UNPROVEN')

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('aar_directory',type=Path)
    print(json.dumps(audit(parser.parse_args().aar_directory),indent=2))
