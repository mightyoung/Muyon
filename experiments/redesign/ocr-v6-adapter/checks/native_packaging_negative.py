"""Negative controls for the native/package checker, using real locked artifacts."""
import argparse
import json
from pathlib import Path
import struct
import tempfile
import zipfile
from native_packaging_audit import audit, elf

def run(aars, apk, ndk):
    results=[]
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        # Minimal real ELF64 with one LOAD: readelf parses it rather than a mock.
        header=b'\x7fELF'+bytes([2,1,1,0])+bytes(8)+struct.pack('<HHIQQQIHHHHHH',3,62,1,0,64,0,0,64,56,1,0,0,0)
        for align,expected in [(4096,False),(16384,True)]:
            blob=header+struct.pack('<IIQQQQQQ',1,5,0,0,0,120,120,align)
            row=elf(blob,tmp/'elf.so')
            assert row['elf16KiBAligned']==expected
            results.append(dict(control=f'LOAD alignment {align}',expected=expected,observed=row['elf16KiBAligned']))
        def repack(name, drop=None, corrupt=None):
            target=tmp/name
            with zipfile.ZipFile(apk) as source,zipfile.ZipFile(target,'w',compression=zipfile.ZIP_STORED) as output:
                for info in source.infolist():
                    if info.filename==drop: continue
                    data=source.read(info.filename)
                    if info.filename==corrupt:data=data[:-1]+bytes([data[-1]^1])
                    output.writestr(info.filename,data)
            return target
        for name,kwargs in [('missing-native',dict(drop='lib/arm64-v8a/libopencv_java4.so')),('corrupt-model',dict(corrupt='assets/ocr-v6/tiny/det/inference.onnx'))]:
            broken=repack(name+'.apk',**kwargs)
            try:audit(aars,broken,ndk)
            except (AssertionError,KeyError) as e: results.append(dict(control=name,status='REJECTED',reason=str(e)))
            else:raise AssertionError('checker accepted '+name)
        unaligned=repack('unaligned.apk')
        report=audit(aars,unaligned,ndk)
        assert report['apkZip16KiBGate']=='FAIL' and report['staticPackagingGate']!='PASS'
        results.append(dict(control='unaligned ZIP',status='REJECTED',observed=report['apkZip16KiBGate']))
        empty_ndk=tmp/'empty-sdk/ndk/empty-ndk';empty_ndk.mkdir(parents=True)
        buildtools=tmp/'empty-sdk/build-tools';buildtools.symlink_to(ndk.parents[1]/'build-tools',target_is_directory=True)
        report=audit(aars,apk,empty_ndk)
        assert report['api26StrongImportGate']=='FAIL' and report['staticPackagingGate']!='PASS'
        results.append(dict(control='missing API26 symbol providers',status='REJECTED',observed=report['api26StrongImportGate']))
    return results

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('aars',type=Path);p.add_argument('apk',type=Path);p.add_argument('ndk',type=Path);a=p.parse_args()
    print(json.dumps(run(a.aars,a.apk,a.ndk),indent=2))
