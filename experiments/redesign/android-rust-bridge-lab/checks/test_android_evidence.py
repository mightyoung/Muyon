"""Synthetic ELF/provenance controls; no NDK/Android result is fabricated."""
import copy
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from elf_check import inspect, ElfInvalid
from android_gate import symbols, api24_imports, AAR_SHA, JNI_SHA, NDK
import package_gate as package


def elf_fixture():
    raw = bytearray(4096)
    raw[:16] = b'\x7fELF\x02\x01\x01' + b'\0' * 9
    struct.pack_into('<HHIQQQIHHHHHH', raw, 16, 3, 183, 1, 0, 64, 0x900, 0, 64, 56, 5, 64, 3, 0)
    programs = [(1, 5, 0, 0, 0, 4096, 4096, 16384),
                (2, 6, 0x400, 0x400, 0, 80, 80, 8),
                (4, 4, 0x500, 0x500, 0, 24, 24, 4),
                (0x6474e552, 4, 0x400, 0x400, 0, 80, 80, 1),
                (0x6474e551, 6, 0, 0, 0, 0, 0, 16)]
    for n, program in enumerate(programs):struct.pack_into('<IIQQQQQQ', raw, 64 + n*56, *program)
    strings = b'\0libc.so\0'; offsets=[]
    for suffix in ['fn_func_bridge_info','fn_func_validate_bundled_contract','checksum_func_bridge_info','checksum_func_validate_bundled_contract']:
        offsets.append(len(strings)); strings += ('uniffi_muyon_android_contract_bridge_' + suffix).encode()+b'\0'
    raw[0x600:0x600+len(strings)] = strings
    for n, entry in enumerate([(5,0x600),(10,len(strings)),(1,1),(30,8),(0,0)]):struct.pack_into('<qQ',raw,0x400+n*16,*entry)
    struct.pack_into('<III8sI',raw,0x500,8,4,1,b'Android\0',24)
    for n, name in enumerate(offsets,1):struct.pack_into('<IBBHQQ',raw,0x700+n*24,name,16,0,1,1,1)
    struct.pack_into('<IIQQQQIIQQ',raw,0x940,0,3,2,0x600,0x600,len(strings),0,0,1,0)
    struct.pack_into('<IIQQQQIIQQ',raw,0x980,0,11,2,0x700,0x700,120,1,1,8,24)
    return raw


class ElfControls(unittest.TestCase):
    def test_synthetic_api24_elf_and_each_boundary_reject(self):
        raw=elf_fixture(); result=inspect(raw,'arm64-v8a')
        self.assertEqual(result['declared_android_api'],24)
        self.assertEqual(result['load_alignments'],[16384])
        unmapped = copy.copy(raw)
        struct.pack_into('<Q', unmapped, 64 + 3*56 + 16, 0x100000)
        with self.assertRaisesRegex(ElfInvalid, '^elf_relro_mapping$'):
            inspect(unmapped, 'arm64-v8a')
        page_tail = copy.copy(raw)
        struct.pack_into('<Q', page_tail, 64 + 3*56 + 40, 16384 - 0x400)
        self.assertTrue(inspect(page_tail, 'arm64-v8a')['relro'])
        struct.pack_into('<Q', page_tail, 64 + 3*56 + 40, 16384 - 0x400 + 1)
        with self.assertRaisesRegex(ElfInvalid, '^elf_relro_mapping$'):
            inspect(page_tail, 'arm64-v8a')
        variants=[]
        bad=copy.copy(raw);struct.pack_into('<H',bad,18,62);variants.append(bad)
        bad=copy.copy(raw);struct.pack_into('<Q',bad,64+48,4096);variants.append(bad)
        bad=copy.copy(raw);struct.pack_into('<I',bad,0x514,26);variants.append(bad)
        bad=copy.copy(raw);struct.pack_into('<Q',bad,0x430+8,0);variants.append(bad)
        bad=copy.copy(raw);struct.pack_into('<I',bad,64+4*56+4,7);variants.append(bad)
        bad=copy.copy(raw);bad[0x600+1:0x600+8]=b'evil.so';variants.append(bad)
        bad=copy.copy(raw);bad[0x850:0x857]=b'GLIBC_2';variants.append(bad)
        bad=copy.copy(raw);struct.pack_into('<I',bad,64+2*56,0);variants.append(bad)
        for bad in variants:
            with self.subTest():
                with self.assertRaises(ElfInvalid):inspect(bad,'arm64-v8a')
        for size in [0,63,100,2048]:
            with self.assertRaises(ElfInvalid):inspect(raw[:size],'arm64-v8a')

    def test_readelf_symbol_parser_and_missing_strong_import_rejects(self):
        self.assertEqual(symbols('  1: 0000 0 FUNC GLOBAL DEFAULT UND malloc@LIBC (2)'),[('GLOBAL','UND','malloc@LIBC')])
        with self.assertRaisesRegex(RuntimeError,'unparsed_dynamic_symbols'):symbols('not readelf output')
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);lib=root/'lib.so';lib.write_bytes(b'fixture')
            stub=root/'toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/24/libc.so'
            stub.parent.mkdir(parents=True);stub.write_bytes(b'fixture stub')
            def fake_run(command, log, env):
                log.write_text('  1: 0000 0 FUNC GLOBAL DEFAULT '+('1 malloc' if command[-1]==stub else 'UND forbidden_api')+'\n')
            with patch('android_gate.run',side_effect=fake_run):
                with self.assertRaisesRegex(RuntimeError,'unresolved_api24_strong_imports:forbidden_api'):
                    api24_imports(lib,{'needed':['libc.so']},'aarch64-linux-android',root,Path('/fixture-readelf'),root,{},'control')


class PackageControls(unittest.TestCase):
    def test_synthetic_matching_source_aggregate_and_stale_hash_reject(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);artifacts=root/'artifacts';artifacts.mkdir();source='a'*40
            binding=root/package.BINDING;binding.parent.mkdir(parents=True);binding.write_bytes(b'fixture binding')
            config=root/package.CONFIG;config.parent.mkdir(parents=True);config.write_bytes(b'fixture config')
            core=root/'core';core.mkdir();(core/'Cargo.lock').write_bytes(b'fixture lock')
            linux=artifacts/'linux';linux.mkdir()
            generated=linux/'android/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt';generated.parent.mkdir(parents=True);generated.write_bytes(binding.read_bytes())
            (linux/'verdict.json').write_text(json.dumps(dict(accepted=True,classification='GREEN',source_sha=source,shipping_features=[],source_inputs_unchanged=True)))
            for abi in package.ABIS:
                directory=artifacts/abi;directory.mkdir();library=directory/'libmuyon_android_contract_bridge.so';library.write_bytes(b'fixture '+abi.encode())
                value=dict(classification='GREEN',source_sha=source,build_identity=source,abi=abi,protocol=1,namespace='muyon_android_contract_bridge',min_api=24,shipping_features=[],ndk_version=NDK,source_inputs_unchanged=True,cargo_lock_sha256=package.sha(core/'Cargo.lock'),android_config_sha256=package.sha(config),jna_aar_sha256=AAR_SHA,jna_jni_sha256=JNI_SHA[abi],library_sha256=package.sha(library))
                (directory/'manifest.json').write_text(json.dumps(value))
            with patch.object(package,'ROOT',root),patch.object(package,'CORE',core):
                value=package.aggregate(artifacts,root/'inputs',source)
                self.assertEqual(set(value['rust_libraries']),set(package.ABIS))
                with self.assertRaisesRegex(RuntimeError,'linux_provenance'):package.aggregate(artifacts,root/'stale','b'*40)
                (artifacts/'x86_64/libmuyon_android_contract_bridge.so').write_bytes(b'modified')
                with self.assertRaisesRegex(RuntimeError,'abi_provenance:x86_64'):package.aggregate(artifacts,root/'modified',source)

    def test_actual_zip_structure_hash_duplicates_and_alignment(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);apk=root/'fixture.apk'
            contents={f'lib/{abi}/{name}':(abi+name).encode() for abi in package.ABIS for name in ['libmuyon_android_contract_bridge.so','libjnidispatch.so']}
            digest=lambda b:hashlib.sha256(b).hexdigest()
            inputs={'rust_libraries':{abi:{'sha256':digest(contents[f'lib/{abi}/libmuyon_android_contract_bridge.so'])} for abi in package.ABIS}}
            jni={abi:digest(contents[f'lib/{abi}/libjnidispatch.so']) for abi in package.ABIS}
            def build(aligned):
                with zipfile.ZipFile(apk,'w') as archive:
                    for name,raw in contents.items():
                        info=zipfile.ZipInfo(name)
                        if aligned:
                            padding=(-archive.fp.tell()-30-len(name)-4)%16384
                            info.extra=struct.pack('<HH',0xcafe,padding)+b'\0'*padding
                        archive.writestr(info,raw)
            with patch.object(package,'JNI_SHA',jni):
                build(True);self.assertEqual(set(package.apk_entries(apk,inputs)),set(contents))
                for unsafe in ['../lib/arm64-v8a/extra.so', '/lib/arm64-v8a/extra.so',
                               'lib/../extra.so', 'assets/./config', 'assets//config',
                               'C:/lib/extra.so', 'lib\\arm64-v8a\\extra.so']:
                    build(True)
                    with zipfile.ZipFile(apk, 'a') as archive:
                        archive.writestr(unsafe, b'not-native-payload')
                    with self.subTest(unsafe=unsafe):
                        with self.assertRaisesRegex(RuntimeError, '^apk_member_path$'):
                            package.apk_entries(apk, inputs)
                build(True)
                with zipfile.ZipFile(apk, 'a') as archive:
                    archive.writestr('assets/safe', b'safe member')
                self.assertEqual(set(package.apk_entries(apk, inputs)), set(contents))
                bad=copy.deepcopy(inputs);bad['rust_libraries']['x86_64']['sha256']='0'*64
                with self.assertRaisesRegex(RuntimeError,'apk_native_hash'):package.apk_entries(apk,bad)
                build(False)
                with self.assertRaisesRegex(RuntimeError,'apk_native_zip_alignment'):package.apk_entries(apk,inputs)


if __name__ == '__main__':unittest.main()
