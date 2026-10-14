"""Thin fixed-input adapter. DUT invocation is oracle-free; compare afterwards."""
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile
from seam import reduce

FIXTURE_SHA='55480f06490983a54e38908b043b06b4b02df451'
FIXTURE_PATH='fixtures/redesign/recovery-minimal-v1/recovery-scenarios.json'
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def invoke_case(case,db_path,engine=reduce):
    # Only this deep copy reaches DUT; no case ID, expected, refs or goldens.
    return engine(copy.deepcopy(case['input']),db_path)


def compare(observations,expected):
    matched=[];unavailable=[];mismatch=[]
    for section in ('required_observations','forbidden_observations'):
        for key,value in expected[section].items():
            if key not in observations:
                unavailable.append(section+'.'+key);continue
            observed=observations[key]
            if section=='forbidden_observations':ok=observed!=value
            elif key.endswith('_one_of'):ok=observed in value
            elif key.endswith('_max') and isinstance(observed,int):ok=observed<=value
            else:ok=observed==value
            (matched if ok else mismatch).append({'assertion':section+'.'+key,'observed':observed,'expected':value})
    return {'matched':matched,'unavailable':unavailable,'mismatches':mismatch}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',default=str(HERE/'observations.json'))
    p.add_argument('--evidence-dir',required=True)
    args=p.parse_args()
    evidence=Path(args.evidence_dir).resolve()
    if evidence.is_relative_to(ROOT):raise ValueError('raw evidence must be outside repository')
    output=Path(args.output).resolve()
    if not output.is_relative_to(HERE):raise ValueError('report must stay in reserved experiment directory')
    evidence.mkdir(parents=True,exist_ok=True)
    raw=subprocess.check_output(['git','-C',str(ROOT),'show',FIXTURE_SHA+':'+FIXTURE_PATH])
    fixture=json.loads(raw);rows=[]
    for group in fixture['groups']:
        for case in group['cases']:
            with tempfile.TemporaryDirectory(prefix='d03a-lab-') as tmp:
                actual=invoke_case(case,str(Path(tmp)/'isolated.sqlite'))
            # The oracle is first read here, after actual independent execution.
            comparison=compare(actual['observations'],case['expected']) if actual['processed'] else {'matched':[],'unavailable':['all_actions_unsupported'],'mismatches':[]}
            status=('fail' if comparison['mismatches'] else 'partial' if actual['gaps'] or comparison['unavailable'] else 'pass') if actual['processed'] else 'not_run'
            rows.append({'case_id':case['case_id'],'group_id':group['group_id'],'historical_v1_status':case['execution_status'],
                         'experiment_status':status,'layer':actual['layer'],'processed_actions':actual['processed'],
                         'actual_observations':actual['observations'],'observation_provenance':actual['observation_provenance'],
                         'action_evidence':actual['action_evidence'],'gaps':actual['gaps'],
                         'comparison':comparison,'product_runtime_status':'not_run','M03_stop_conditions':actual['gaps']+comparison['unavailable']})
    report={'format':'d03a-experimental-observations-v1','fixture_source_sha':FIXTURE_SHA,
            'fixture_sha256':hashlib.sha256(raw).hexdigest(),'worktree_base_sha':subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip(),
            'python_version':platform.python_version(),'sqlite_version':__import__('sqlite3').sqlite_version,
            'implementation_sha256':{n:hashlib.sha256((HERE/n).read_bytes()).hexdigest() for n in ['seam.py','run_experiment.py']},
            'summary':dict(collections.Counter(r['experiment_status'] for r in rows)),
            'matched_assertions':sum(len(r['comparison']['matched']) for r in rows),
            'mismatched_assertions':sum(len(r['comparison']['mismatches']) for r in rows),
            'complete_fixture_operation_passes':sum(r['experiment_status']=='pass' for r in rows),
            'matching_assertions_are_not_complete_operation_evidence':True,
            'scope':'independent experimental Python reducer and isolated SQLite lab only; not Rust frozen core/schema/IPC/native',
            'M03':'blocked_contract','old_v1_unmodified':True,'runtime_gate_52':'not_run','classification_29':'not_run','cases':rows}
    output.write_text(json.dumps(report,ensure_ascii=True,indent=2)+'\n')
    (evidence/'scenario-summary.json').write_text(json.dumps({k:report[k] for k in ['summary','matched_assertions','mismatched_assertions']},indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['summary','matched_assertions','mismatched_assertions']}))
    return int(report['mismatched_assertions']>0)

if __name__=='__main__':raise SystemExit(main())
