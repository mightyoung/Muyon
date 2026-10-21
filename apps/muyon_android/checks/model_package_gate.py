#!/usr/bin/env python3
"""Inspect frozen model bytes and every packaged native library; no runtime claim."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

def check(apk, assets, native):
    manifest = json.loads((assets / "local-models/manifest.json").read_text())
    result = []
    with zipfile.ZipFile(apk) as archive:
        for notice in ("LOCAL_MODELS.txt", "llama-MIT.txt", "onnxruntime-MIT.txt", "PaddleOCR-Apache2.txt"):
            assert archive.read("assets/notices/" + notice), notice
        for name, identity in manifest.items():
            value = archive.read("assets/local-models/" + name)
            assert len(value) == identity["bytes"]
            assert hashlib.sha256(value).hexdigest() == identity["sha256"], name
        libraries = [name for name in archive.namelist() if name.startswith("lib/") and name.endswith(".so")]
        for name in libraries:
            value = archive.read(name)
            abi = name.split("/")[1]
            assert abi in ("arm64-v8a", "x86_64")
            assert value[:6] == b"\x7fELF\x02\x01"
            assert struct.unpack_from("<H", value, 18)[0] == {"arm64-v8a":183, "x86_64":62}[abi]
            offset = struct.unpack_from("<Q", value, 32)[0]
            size, count = struct.unpack_from("<HH", value, 54)
            aligns = []
            for index in range(count):
                kind, _, file_offset, address, _, _, _, align = struct.unpack_from("<IIQQQQQQ", value, offset + index * size)
                if kind == 1:
                    assert align >= 16384 and file_offset % align == address % align, name
                    aligns.append(align)
            assert aligns
            info = archive.getinfo(name)
            with apk.open("rb") as stream:
                stream.seek(info.header_offset + 26)
                filename, extra = struct.unpack("<HH", stream.read(4))
            assert info.compress_type == zipfile.ZIP_STORED
            assert (info.header_offset + 30 + filename + extra) % 16384 == 0, name
            if name.endswith("libmuyon_local_embedding.so"):
                assert value == (native / abi / "libmuyon_local_embedding.so").read_bytes()
            result.append({"name": name, "sha256": hashlib.sha256(value).hexdigest(), "alignment": min(aligns)})
        for abi in ("arm64-v8a", "x86_64"):
            for library in ("libmuyon_local_embedding.so", "libonnxruntime.so", "libonnxruntime4j_jni.so"):
                assert f"lib/{abi}/{library}" in libraries
    return {"gate":"PASS", "model_files":len(manifest), "libraries":result,
            "boundary":"Static APK bytes/alignment only; API26 inference and 16KiB-kernel execution are separate evidence."}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("assets", type=Path)
    parser.add_argument("native", type=Path)
    args = parser.parse_args()
    print(json.dumps(check(args.apk,args.assets,args.native),indent=2))
