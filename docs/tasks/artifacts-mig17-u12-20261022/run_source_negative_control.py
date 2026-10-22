#!/usr/bin/env python3
"""Run real behavioral regressions with ONLY the live binding-source guard removed.
Disposable source copy, no production edits. Expected test failures establish the
guard catches source publication and receipt-tail revocation, not just lease TTL.
"""
import pathlib, shutil, subprocess, tempfile
repo=pathlib.Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='muyon-source-red-') as temporary:
    copy=pathlib.Path(temporary)
    for name in filter(None,subprocess.check_output(['git','ls-files','-z'],cwd=repo).decode().split('\0')):
        source=repo/name
        if source.is_file():
            target=copy/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
    for name in ['crates/muyon-core/src/artifacts','docs/tasks/artifacts-mig17-u12-20261022']:
        shutil.copytree(repo/name,copy/name,dirs_exist_ok=True)
    source=copy/'crates/muyon-core/src/artifacts/local_sources.rs'
    text=source.read_text();old='self.validate_local_evidence_snapshot(tx, a, &snapshot)'
    if old not in text:old='self.validate_local_evidence_snapshot(tx,a,&snapshot)'
    assert text.count(old)==1
    source.write_text(text.replace(old,'Ok(()) // NEGATIVE CONTROL: skip live original-source authorization'))
    statuses=[]
    for name in ['source_head_change_invalidates','receipt_tail_source_revocation']:
        print('NEGATIVE CONTROL, only live guard removed:',name,flush=True)
        status=subprocess.run(['python3',str(copy/'docs/tasks/artifacts-mig17-u12-20261022/run_source_combination.py'),'--repo',str(copy),'--source-label','negative-control-only-live-guard-removed','--filter','artifacts::local_interactions::source_tests::'+name]).returncode
        statuses.append(status)
    print('Observed expected nonzero behavioral results:',statuses,flush=True)
    raise SystemExit(0 if statuses==[101,101] else 1)
