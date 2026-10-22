#!/usr/bin/env python3
"""Compose immutable document core and owned group sources only in a temp tree."""
import os, pathlib, re, shutil, subprocess, tarfile, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[3]
TASK=pathlib.Path(__file__).resolve().parent
PIN='10d3aa83e2a93581107ad2e9f44331b5ea99d866'
env=os.environ.copy()
env.update(PATH='/tmp/mig20-rust/bin:'+env['PATH'],CARGO_HOME='/tmp/mig20-cargo',CARGO_TARGET_DIR='/tmp/mig20-target',RUSTFLAGS='-L native=/tmp/mig20-native-libs')
with tempfile.TemporaryDirectory(prefix='mig20-combined-') as tmp:
    tmp=pathlib.Path(tmp);snapshot=tmp/'snapshot';snapshot.mkdir();runner=tmp/'runner';runner.mkdir()
    archive=tmp/'source.tar'
    with archive.open('wb') as output: subprocess.run(['git','archive',PIN],cwd=ROOT,stdout=output,check=True)
    with tarfile.open(archive) as source: source.extractall(snapshot,filter='data')
    core=snapshot/'crates/muyon-core'
    for module in ['group_governance','group_runtime']:
        shutil.copytree(ROOT/'crates/muyon-core/src'/module,core/'src'/module)
    # The only lib mutation is application of the delivered patch in this disposable snapshot.
    with (TASK/'CORE-EXPORT.patch').open('rb') as patch:
        subprocess.run(['patch','-p1'],cwd=snapshot,stdin=patch,check=True)
    manifest=(TASK/'evidence/independent-review-Cargo.toml').read_text().split('[[test]]')[0]
    manifest=manifest.replace('mig20-independent-review','mig20-config-combination')
    manifest=manifest.replace('/workspace/mig20/experiments/',str(snapshot/'experiments')+'/')
    manifest+='muyon-core={path="'+str(core)+'"}\n'
    for name in ['group_runtime_bridge','group_runtime_store']:
        test=(ROOT/'crates/muyon-core/tests'/(name+'.rs')).read_text()
        test=test.replace('#![allow(dead_code)]','#![allow(dead_code)]\n#[path = "../src/documents/mod.rs"]\nmod documents;')
        test=re.sub(r'#\[path = "../src/([^"]+)"\]',lambda m:'#[path = "'+str(core/'src'/m[1])+'"]',test)
        (runner/(name+'.rs')).write_text(test)
        manifest+='\n[[test]]\nname="'+name+'"\npath="'+name+'.rs"\n'
    (runner/'Cargo.toml').write_text(manifest)
    shutil.copyfile(TASK/'evidence/combination-runner.Cargo.lock',runner/'Cargo.lock')
    result=subprocess.run(['/tmp/mig20-rust/bin/cargo','test','--manifest-path',str(runner/'Cargo.toml'),'--offline','--locked'],env=env)
    print('COMBINATION_EXIT='+str(result.returncode),flush=True)
    raise SystemExit(result.returncode)
