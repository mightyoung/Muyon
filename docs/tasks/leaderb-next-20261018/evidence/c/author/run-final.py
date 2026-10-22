import ctypes, hashlib, json, os, platform, subprocess, time
from pathlib import Path
root=Path('/workspace/leaderb-store')
out=Path(__file__).parent
sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert sha=='a4f8604ec7439da2dc66fb6145101d9f9e25fc5f'
paths=[os.fsdecode(p) for p in subprocess.check_output(['git','ls-files','-z'],cwd=root).split(b'\0') if p]
hashes=lambda:{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
before=hashes()
env=dict(os.environ,CARGO_HOME='/workspace/toolchains/store-rust/cargo',RUSTUP_HOME='/workspace/toolchains/store-rust/rustup',CARGO_TARGET_DIR='/workspace/toolchains/store-rust/target-1.99.0')
cargo='/workspace/toolchains/store-rust/cargo/bin/cargo'
manifest='experiments/redesign/rust-agent-host-lab/core/Cargo.toml'
commands=[('supplier-store',[cargo,'+1.99.0','test','--manifest-path',manifest,'--locked','--offline','--test','supplier_store','--','--nocapture']),('offline-service-runtime',[cargo,'+1.99.0','test','--manifest-path',manifest,'--locked','--offline','--test','service_runtime','--','--nocapture']),('android-lib-check',[cargo,'+1.99.0','check','--manifest-path',manifest,'--locked','--offline','--target','aarch64-linux-android','--lib']),('format',['/workspace/toolchains/store-rust/cargo/bin/rustfmt','+1.99.0','--edition','2021','--check','experiments/redesign/rust-agent-host-lab/core/src/supplier_store.rs','experiments/redesign/rust-agent-host-lab/core/src/supplier_sqlite.rs','experiments/redesign/rust-agent-host-lab/core/tests/supplier_store.rs']),('diff-check',['git','diff','--check'])]
results=[]
for name,command in commands:
    started=time.time()
    r=subprocess.run(command,cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/(name+'.log')).write_bytes(r.stdout)
    results.append(dict(name=name,command=command,exit=r.returncode,source_sha=sha,started_unix=started,finished_unix=time.time(),log_sha256=hashlib.sha256(r.stdout).hexdigest()))
    print(name,r.returncode,flush=True)
sqlite=ctypes.CDLL('libsqlite3.so.0');sqlite.sqlite3_libversion.restype=ctypes.c_char_p
status=subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True)
after=hashes()
report=dict(source_sha=sha,commands=results,native_sqlite=sqlite.sqlite3_libversion().decode(),platform=platform.platform(),source_unchanged=before==after and not status,git_status=status,source_before=before,source_after=after)
(out/'MANIFEST.json').write_text(json.dumps(report,indent=2)+'\n')
assert report['source_unchanged']
assert all(r['exit']==0 for r in results)
