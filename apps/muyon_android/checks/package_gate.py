#!/usr/bin/env python3
"""Verify this product's two native ABIs and generated bridge, without executing them."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import struct
import subprocess
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def check(apk, inputs, generated, checked):
    assert generated.read_bytes() == checked.read_bytes(), "generated bridge bytes differ"
    expected = dict(line.split()[::-1] for line in (inputs.parent / "SHA256SUMS").read_text().splitlines())
    expected_abis = {"arm64-v8a": 183, "x86_64": 62}
    host = {"Darwin": "darwin-x86_64", "Linux": "linux-x86_64"}[platform.system()]
    readelf = Path(os.environ["ANDROID_HOME"]) / f"ndk/28.2.13676358/toolchains/llvm/prebuilt/{host}/bin/llvm-readelf"
    libraries = []
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), "duplicate APK entry"
        native = [name for name in names if name.startswith("lib/") and name.endswith(".so")]
        assert {name.split('/')[1] for name in native} == set(expected_abis), "ABI set differs"
        for abi, machine in expected_abis.items():
            name = f"lib/{abi}/libmuyon_android_product.so"
            data = archive.read(name)
            assert digest(data) == expected[f"{abi}/libmuyon_android_product.so"], f"APK/product hash mismatch: {abi}"
            assert digest((inputs / abi / "libmuyon_android_product.so").read_bytes()) == digest(data)
            info = archive.getinfo(name)
            with apk.open("rb") as stream:
                stream.seek(info.header_offset + 26)
                filename_length, extra_length = struct.unpack("<HH", stream.read(4))
            data_offset = info.header_offset + 30 + filename_length + extra_length
            assert info.compress_type == zipfile.ZIP_STORED and data_offset % 16384 == 0, "APK native alignment differs"
            assert data[:6] == b"\x7fELF\x02\x01", "expected ELF64 little-endian"
            assert struct.unpack_from("<H", data, 18)[0] == machine, "ELF architecture mismatch"
            phoff = struct.unpack_from("<Q", data, 32)[0]
            phsize, phnum = struct.unpack_from("<HH", data, 54)
            segments = []
            for index in range(phnum):
                kind, _, offset, vaddr, _, _, _, align = struct.unpack_from("<IIQQQQQQ", data, phoff + index * phsize)
                if kind == 1:
                    assert align >= 16384 and offset % align == vaddr % align, "ELF LOAD alignment differs"
                    segments.append(align)
            assert segments
            dynamic = subprocess.run([str(readelf), "-d", str(inputs / abi / "libmuyon_android_product.so")], check=True, capture_output=True, text=True).stdout
            assert "libsqlite" not in dynamic.lower(), "hidden Android SQLite dependency"
            libraries.append({"abi": abi, "sha256": digest(data), "load_alignments": segments, "apk_data_offset": data_offset})
    return {"gate": "PASS", "apk_sha256": digest(apk.read_bytes()),
            "build_id": (inputs.parent / "build-id.txt").read_text().strip(),
            "generated_bridge_sha256": digest(checked.read_bytes()), "libraries": libraries,
            "boundary": "packaging only; runtime identity is separately asserted on API26"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("inputs", type=Path)
    parser.add_argument("generated", type=Path)
    parser.add_argument("checked", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(check(arguments.apk, arguments.inputs, arguments.generated, arguments.checked), indent=2))
