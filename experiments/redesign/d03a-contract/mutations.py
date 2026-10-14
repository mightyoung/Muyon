"""Run three necessary inverse mutations, restore byte-identical DUT, recheck.

Mutations affect only the reserved experimental source, never product code.
Raw test logs stay outside repository. Each mutation must cause AssertionError
in its named safety test, not an import/compile failure.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--evidence-dir',required=True)
    args=p.parse_args();evidence=Path(args.evidence_dir).resolve()
    if evidence.is_relative_to(ROOT):raise ValueError('raw logs outside repository required')
    evidence.mkdir(parents=True,exist_ok=True)
    source=HERE/'seam.py';original=source.read_bytes();text=original.decode();rows=[]
    specifications=[
        ('remove_full_domain_rejection','if domain(c)!=domain(current):','if False: # inverse mutation',
         'test_domain_rejects_larger_seq_from_each_wrong_identity'),
        ('old_epoch_erases_real_receipt_hint','hint=copy.deepcopy(a);',"hint=copy.deepcopy(a) if a.get('epoch')==epoch else None;",
         'test_old_epoch_display_rejected_but_ledger_lookup_preserves_effect'),
        ('premature_commit_between_projection_and_cursor',"if fault=='after_state_write':os._exit(77)","db.commit()\n        if fault=='after_state_write':os._exit(77)",
         'test_process_exit_between_state_and_cursor_rolls_back')]
    command=[sys.executable,'-B','-m','unittest','discover','-s',str(HERE/'tests'),'-v']
    try:
        for name,before,after,target in specifications:
            if text.count(before)!=1:raise ValueError('mutation site not unique: '+name)
            candidate=text.replace(before,after,1);source.write_text(candidate)
            run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
            log=run.stdout+run.stderr;(evidence/(name+'.log')).write_text(log)
            failures=re.findall(r'^FAIL: (\w+)',log,re.M)
            if run.returncode==0 or target not in failures or 'AssertionError' not in log or re.search(r'^ERROR:',log,re.M):
                raise ValueError('mutation lacks required behavioral RED: '+name)
            rows.append({'mutation':name,'exit_code':run.returncode,'failed_tests':failures,
                         'mutated_source_sha256':hashlib.sha256(candidate.encode()).hexdigest(),
                         'required_safety_test':target,'behavioral_red':True})
            source.write_bytes(original)
    finally:
        source.write_bytes(original)
    final=subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
    (evidence/'mutation-restored-green.log').write_text(final.stdout+final.stderr)
    if final.returncode:raise ValueError('restored suite failed')
    report={'baseline_source_sha256':hashlib.sha256(original).hexdigest(),
            'restored_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'mutations':rows,'restored_suite_exit_code':final.returncode,
            'scope':'independent experiment inverse mutations, not product/core mutation gate'}
    (HERE/'mutation-observations.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'behavioral_red_mutations':len(rows),'mutation_exits':[r['exit_code'] for r in rows],'restored_exit':final.returncode}))
    return 0

if __name__=='__main__':raise SystemExit(main())
