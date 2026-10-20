"""Reproducible ZIP32 fixtures. Python standard library only."""
import io
from pathlib import Path
import zipfile
import struct

ROOT = Path(__file__).parent
class NonSeekable(io.BytesIO):
    def seekable(self):
        return False
    def seek(self, *args):
        raise io.UnsupportedOperation("stream")

for name, method, stream in [
    ("stored.zip", zipfile.ZIP_STORED, False),
    ("deflated.zip", zipfile.ZIP_DEFLATED, False),
    ("descriptor.zip", zipfile.ZIP_DEFLATED, True),
]:
    output = NonSeekable() if stream else io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=method) as archive:
        info = zipfile.ZipInfo("论文/测试.json", date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = method
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        archive.writestr(info, b'{"title":"sample"}')
    (ROOT / name).write_bytes(output.getvalue())

for name, extra in [("unknown-extra.zip", b'\x34\x12\x00\x00'), ("zip64-extra.zip", b'\x01\x00\x00\x00')]:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        info = zipfile.ZipInfo("entry", date_time=(2026, 1, 1, 0, 0, 0))
        info.extra = extra
        archive.writestr(info, b"sample")
    (ROOT / name).write_bytes(output.getvalue())

# A valid inner local header lives inside outer's stored payload. Both CEN
# records are internally consistent, but their physical file extents overlap.
def local(name, content):
    crc = zipfile.crc32(content)
    return struct.pack('<IHHHHHIIIHH', 0x04034b50, 20, 0, 0, 0, 0, crc, len(content), len(content), len(name), 0) + name + content
def central(name, content, offset):
    crc = zipfile.crc32(content)
    return struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 20, 20, 0, 0, 0, 0, crc, len(content), len(content), len(name), 0, 0, 0, 0, 0, offset) + name
inner = local(b'inner', b'payload')
outer = local(b'outer', inner)
cd = central(b'outer', inner, 0) + central(b'inner', b'payload', 35)
eocd = struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, 2, 2, len(cd), len(outer), 0)
(ROOT / 'overlap.zip').write_bytes(outer + cd + eocd)

output = io.BytesIO()
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for i in range(6):
        archive.writestr(f'entry{i}', b'x')
quota = bytearray(output.getvalue())
start = 0
while True:
    at = quota.find(b'PK\x01\x02', start)
    if at < 0:
        break
    offset = struct.unpack_from('<I', quota, at+42)[0]
    struct.pack_into('<I', quota, at+24, 30*1024*1024)
    struct.pack_into('<I', quota, offset+22, 30*1024*1024)
    start = at+46
(ROOT / 'aggregate-limit.zip').write_bytes(quota)

for name, mode in [("symlink.zip", 0o120777), ("fifo.zip", 0o010644), ("device.zip", 0o020644)]:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        info = zipfile.ZipInfo("bad", date_time=(2026, 1, 1, 0, 0, 0))
        info.create_system = 3
        info.external_attr = mode << 16
        archive.writestr(info, b"target")
    (ROOT / name).write_bytes(output.getvalue())

for name, members in [
    ("traversal.zip", ["../escape"]),
    ("absolute.zip", ["/escape"]),
    ("backslash.zip", ["a\\b"]),
    ("drive.zip", ["C:escape"]),
    ("empty-part.zip", ["a//b"]),
    ("duplicate.zip", ["same", "same"]),
    ("unicode-alias.zip", ["e\u0301.json", "é.json"]),
    ("prefix-file.zip", ["a", "a/b"]),
    ("directories.zip", ["a/", "a/b.json"]),
]:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for member in members:
            info = zipfile.ZipInfo(member, date_time=(2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            directory = member.endswith("/")
            info.external_attr = ((0o040755 << 16) | 0x10) if directory else (0o100644 << 16)
            archive.writestr(info, b"" if directory else b"sample")
    (ROOT / name).write_bytes(output.getvalue())
