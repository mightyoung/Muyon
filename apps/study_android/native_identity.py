#!/usr/bin/env python3
import hashlib,json,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[2]
sources=[root/'crates/Cargo.lock',root/'crates/muyon-core/src/sqlite.rs',*sorted((root/'crates/muyon-core/src/study').glob('*.rs')),*sorted((root/'crates/muyon-study-ffi').rglob('*.rs'))]
h=hashlib.sha256()
for p in sources:h.update(str(p.relative_to(root)).encode()+b'\0'+p.read_bytes())
directory=root/'apps/study_android/app/src/main/jniLibs'
manifest=directory/'source.json'
value={'source':h.hexdigest(),'libraries':{abi:hashlib.sha256((directory/abi/'libmuyon_study.so').read_bytes()).hexdigest()for abi in ['arm64-v8a','x86_64']}}
if '--write' in sys.argv:manifest.write_text(json.dumps(value,indent=2)+'\n')
else:assert json.loads(manifest.read_text())==value,'Rebuild native libraries from current source'
print(value['source'])
