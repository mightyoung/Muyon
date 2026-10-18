"""Audit immutable AAR inputs and real APK output; never claim device execution."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import zipfile

PINS = {
 'ort': ('com.microsoft.onnxruntime:onnxruntime-android:1.21.1', '30e594a4b9246fe3ca25768570e90f71e6d33ceb7b7dd72f92dcd7c267611d3f'),
 'opencv': ('org.opencv:opencv:4.12.0', 'f71846a313388d9da667a59be1e921669fcf792d1ba264b3898253ca789bc3f0'),
}
ABI_TRIPLES = {'arm64-v8a':'aarch64-linux-android','x86_64':'x86_64-linux-android','armeabi-v7a':'arm-linux-androideabi','x86':'i686-linux-android'}

def sha(data): return hashlib.sha256(data).hexdigest()

def elf(data, path):
    assert data[:4] == b'\x7fELF' and data[5] == 1
    wide = data[4] == 2
    header = struct.unpack_from('<HHIQQQIHHHHHH' if wide else '<HHIIIIIHHHHHH', data,16)
    offset, size, count = header[4], header[8], header[9]
    segments=[]
    for i in range(count):
        p=struct.unpack_from('<IIQQQQQQ' if wide else '<IIIIIIII',data,offset+i*size)
        typ,flags,off,addr,filesz,memsz,align = (p[0],p[1],p[2],p[3],p[5],p[6],p[7]) if wide else (p[0],p[6],p[1],p[2],p[4],p[5],p[7])
        segments.append(dict(type=typ,flags=flags,offset=off,vaddr=addr,filesz=filesz,memsz=memsz,align=align))
    loads=[p for p in segments if p['type']==1]
    relros=[p for p in segments if p['type']==0x6474e552]
    for r in relros:
        end=r['vaddr']+r['memsz']; rounded=(end+16383)//16384*16384
        # Also accept an isolated RELRO LOAD only when no writable byte follows
        # before the next page boundary (Android documentation's exception).
        r['endModulo16KiB']=end%16384
        r['safe16KiB']=all(not (p['flags']&2) or max(end,p['vaddr']) >= min(rounded,p['vaddr']+p['memsz']) for p in loads)
    path.write_bytes(data)
    dynamic=subprocess.check_output(['readelf','-dW',str(path)],text=True)
    symbols=subprocess.check_output(['readelf','--dyn-syms','-W',str(path)],text=True)
    imports=[]; exports=[]
    for line in symbols.splitlines():
        cols=line.split()
        if len(cols)<8 or not cols[0].endswith(':'): continue
        symbol=cols[7].split('@')[0]
        if cols[6]=='UND': imports.append(dict(name=symbol,weak=cols[4]=='WEAK',version=cols[7]))
        elif cols[4] in ('GLOBAL','WEAK'):
            exports.append(symbol)
            if '@' in cols[7]: exports.append(cols[7].replace('@@','@'))
    return dict(bytes=len(data),sha256=sha(data),bits=64 if wide else 32,loadSegments=loads,relroSegments=relros,
        elf16KiBAligned=bool(loads) and all(p['align']>=16384 and (p['vaddr']-p['offset'])%16384==0 for p in loads) and all(r['safe16KiB'] for r in relros),
        needed=re.findall(r'\(NEEDED\).*?\[(.*?)\]',dynamic),imports=imports,exports=exports)

def audit(aars,apk=None,ndk=None,adapter_aar=None):
    result=dict(artifacts={},libraries=[],deviceApi26='NOT_RUN',device16KiB='NOT_RUN',androidDetRecParity='NOT_RUN')
    with tempfile.TemporaryDirectory() as tmp:
        binary=Path(tmp)/'lib.so'
        for name,(coordinate,digest) in PINS.items():
            file=aars/(name+'.aar'); data=file.read_bytes(); assert sha(data)==digest,coordinate
            with zipfile.ZipFile(file) as z:
                result['artifacts'][name]=dict(coordinate=coordinate,sha256=digest,manifest=z.read('AndroidManifest.xml').decode())
                for entry in z.namelist():
                    if entry.startswith('jni/') and entry.endswith('.so'):
                        row=elf(z.read(entry),binary);row.update(artifact=name,entry=entry,abi=entry.split('/')[1]);result['libraries'].append(row)
        if ndk:
            sysroot=ndk/'toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib'
            for row in result['libraries']:
                providers={}
                for other in result['libraries']:
                    if other['abi']==row['abi']:providers[other['entry'].split('/')[-1]]=set(other['exports'])
                pending=list(row['needed']);visited=set();available=set();missing_libs=[];stubs=[]
                while pending:
                    name=pending.pop()
                    if name in visited:continue
                    visited.add(name)
                    if name in providers:available.update(providers[name]);continue
                    stub=sysroot/ABI_TRIPLES[row['abi']]/'26'/name
                    if not stub.is_file():missing_libs.append(name);continue
                    evidence=elf(stub.read_bytes(),binary);available.update(evidence['exports']);pending.extend(evidence['needed']);stubs.append(dict(name=name,sha256=evidence['sha256']))
                missing=[p for p in row['imports'] if not p['weak'] and p['version'].replace('@@','@') not in available]
                row['api26ImportCheck']=dict(status='PASS' if not missing and not missing_libs else 'FAIL',missing=missing,missingLibraries=missing_libs,ndkApi26Stubs=stubs)
        if apk:
            with zipfile.ZipFile(apk) as z,apk.open('rb') as raw:
                entries=[]
                for info in z.infolist():
                    if not info.filename.startswith('lib/') or not info.filename.endswith('.so'):continue
                    raw.seek(info.header_offset);header=raw.read(30);name_len,extra_len=struct.unpack_from('<HH',header,26)
                    off=info.header_offset+30+name_len+extra_len
                    entry=elf(z.read(info),binary);entry.update(entry=info.filename,dataOffset=off,compression=info.compress_type,zip16KiBAligned=info.compress_type==0 and off%16384==0);entries.append(entry)
                expected_libraries={'lib/'+r['entry'].removeprefix('jni/'):r for r in result['libraries']}
                actual_libraries={r['entry']:r for r in entries}
                assert len(actual_libraries)==len(entries), 'duplicate APK native entry'
                assert actual_libraries.keys()==expected_libraries.keys(), 'APK native library set differs from locked AARs'
                for name,row in actual_libraries.items():
                    assert row['sha256']==expected_libraries[name]['sha256'], 'APK native bytes differ from locked AAR: '+name
                expected=json.loads((Path(__file__).resolve().parents[1]/'models.lock.json').read_text())
                assets=[]
                for model in expected['models']:
                    repo=model['repository'].split('/')[-1]
                    if not repo.startswith('PP-OCRv6_tiny_'):continue
                    kind='det' if '_det_' in repo else 'rec'
                    for f in model['files']:
                        if f['file']!='inference.onnx' and not (kind=='rec' and f['file']=='inference.yml'):continue
                        name=f"assets/ocr-v6/tiny/{kind}/{f['file']}";data=z.read(name)
                        assert sha(data)==f['sha256'] and len(data)==f['bytes'],name
                        assets.append(dict(entry=name,bytes=len(data),sha256=sha(data)))
                assert len(assets)==3
                result['apk']=dict(file=str(apk),sha256=sha(apk.read_bytes()),bytes=apk.stat().st_size,libraries=entries,verifiedAssets=assets)
            if ndk:
                aapt=ndk.parents[1]/'build-tools/36.0.0/aapt'
                badging=subprocess.check_output([str(aapt),'dump','badging',str(apk)],text=True)
                assert "sdkVersion:'26'" in badging, 'APK minSdk is not 26'
                result['apk']['manifestMinSdk']=26
                result['apk']['manifestBadgingSha256']=sha(badging.encode())
    if adapter_aar:
        with zipfile.ZipFile(adapter_aar) as z:
            manifest=z.read('AndroidManifest.xml').decode()
            assert re.search(r'minSdkVersion="26"',manifest), 'adapter AAR minSdk is not 26'
            for asset in result.get('apk',{}).get('verifiedAssets',[]):
                assert sha(z.read(asset['entry']))==asset['sha256'], 'AAR asset differs: '+asset['entry']
            result['adapterAar']=dict(file=str(adapter_aar),sha256=sha(adapter_aar.read_bytes()),bytes=adapter_aar.stat().st_size,manifest=manifest,classesJarSha256=sha(z.read('classes.jar')))
    for row in result['libraries'] + result.get('apk',{}).get('libraries',[]):
        for field in ['imports','exports']:
            symbols=row.pop(field)
            row[field+'Count']=len(symbols)
            row[field+'Sha256']=sha(json.dumps(symbols,sort_keys=True).encode())
    all64=[r for r in result['libraries'] if r['bits']==64]
    result['static64BitElfGate']='PASS' if all64 and all(r['elf16KiBAligned'] for r in all64) else 'FAIL'
    result['api26StrongImportGate']=('PASS' if all(r['api26ImportCheck']['status']=='PASS' for r in result['libraries']) else 'FAIL') if ndk else 'NOT_RUN'
    result['apkMinSdk26Gate']='PASS' if result.get('apk',{}).get('manifestMinSdk')==26 else 'NOT_RUN'
    result['apkZip16KiBGate']=('PASS' if result['apk']['libraries'] and all(r['zip16KiBAligned'] for r in result['apk']['libraries']) else 'FAIL') if apk else 'NOT_RUN'
    result['apk64BitElfGate']=('PASS' if all(r['elf16KiBAligned'] for r in result['apk']['libraries'] if r['bits']==64) else 'FAIL') if apk else 'NOT_RUN'
    result['staticPackagingGate']='PASS' if all(result[k]=='PASS' for k in ['static64BitElfGate','api26StrongImportGate','apkZip16KiBGate','apk64BitElfGate','apkMinSdk26Gate']) else 'INCOMPLETE_OR_FAIL'
    result['shippingGate']='NOT_RUN_DEVICE_AND_HOST_INTEGRATION'
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('aars',type=Path);p.add_argument('--apk',type=Path);p.add_argument('--ndk',type=Path);p.add_argument('--adapter-aar',type=Path);p.add_argument('--require-static-pass',action='store_true');a=p.parse_args()
    report=audit(a.aars,a.apk,a.ndk,a.adapter_aar);print(json.dumps(report,indent=2))
    if a.require_static_pass and report['staticPackagingGate']!='PASS': raise SystemExit(1)
