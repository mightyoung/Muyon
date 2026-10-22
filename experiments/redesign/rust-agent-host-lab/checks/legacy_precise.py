"""Run all sixteen exact baseline/mutant pairs; broad legacy17 remains a separate required gate."""
import ast,json,os,sys,shutil,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'android-rust-bridge-lab/checks'))
from linux_gate import run,sha
from legacy_semantics import accepted
CONTRACTS=[
 ('wire_stale_reported_usage','wire','prior_usage_is_unknown_on_later_failed_turn_and_reopen',['left: "5"','right: "unknown"']),
 ('wire_private_history_bound','wire','escaped_private_history_remains_loadable_without_relaxing_wire_limit',['error=wire_json_size']),
 ('wire_container_depth','wire_review','exactly_32_container_levels_accept_and_33_reject',['33 containers exceed the frozen limit']),
 ('wire_native_value_identity','wire_review','tool_result_value_must_match_its_paired_call',['a paired ID cannot conceal changed original value']),
 ('wire_stream_cancel_bypass','wire','silent_stream_cancellation_is_observed_before_timeout',['right: "wire_cancelled"']),
 ('wire_missing_done','http_transport','partial_sse_never_becomes_a_tool_event',['left: "wire_tool_finish"','right: "wire_stream_truncated"']),
 ('wire_native_pair','wire','encoder_structure_exact_schema_and_role_pair_are_verified',['left: String("wrong-pair")','right: String("c1")']),
 ('wire_budget_bypass','wire','wire_budget_stops_before_request_and_does_not_reset',['left: "1"','right: "0"']),
 ('hard_policy_bypass','kernel','read_only_and_hard_gates_deny',['left: Permit','right: Denied']),
 ('unknown_redispatch','kernel','corrupt_or_absent_original_evidence_never_replays_unknown',['assertion failed:','model_calls=1']),
 ('duplicate_effect','kernel','physical_binding_replay_returns_original_and_altered_binding_conflicts',['receipt_identity']),
 ('pre_effect_context_bypass','kernel','tool_result_context_budget_is_admitted_before_first_effect_or_confirmation',['assertion failed:','effects=0']),
 ('terminal_resurrection','kernel','restoring_receipt_preserves_completed_control_barrier',['assertion']),
 ('cached_receipt_trust','kernel','cached_completed_projection_cannot_replace_original_evidence',['assertion failed:','status=outcome_unknown']),
 ('receipt_current_binding_only','kernel','historical_receipt_hold_preserves_new_waiting_binding_and_confirmation',['assertion failed:','status=outcome_unknown']),
 ('budget_reset','kernel','exhausted_budget_survives_reopen_and_does_not_request_followup',['assertion']),
]
def main():
 import argparse
 parser=argparse.ArgumentParser()
 for name in ('source-root','evidence-dir','work-dir'):parser.add_argument('--'+name,type=Path,required=True)
 args=parser.parse_args();ROOT=args.source_root.resolve();E=args.evidence_dir.resolve();ev=E;ev.mkdir();work=args.work_dir.resolve();core=ROOT/'experiments/redesign/core-agent-lab/core'
 identity={'source_sha':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()}
 shutil.copytree(core,work,ignore=shutil.ignore_patterns('target','__pycache__'))
 tree=ast.parse((core/'mutations.py').read_text());mutations=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='mutations' for t in n.targets));defs={x[0]:x[1:] for x in mutations};original={path:(core/path).read_text() for path,_,_ in defs.values()}
 baseline_env=dict(os.environ,CARGO_TARGET_DIR=str(work/'baseline-target'));env=dict(os.environ,CARGO_TARGET_DIR=str(work/'target'));rows=[]
 for name,target,test,needles in CONTRACTS:
  item=ev/name;item.mkdir();cmd=['cargo','test','--offline','--locked','--test',target,test,'--','--exact','--nocapture']
  status=run(cmd,item/'baseline.log',baseline_env,cwd=core,timeout=120,required=False);base=json.loads((item/'baseline.log.json').read_text());baseline=status==0 and f'test {test} ... ok' in (item/'baseline.log').read_text() and not base['timed_out'] and not base['forced_owned_group_cleanup'] and not base['live_after_cleanup']
  for path,text in original.items():(work/path).write_text(text)
  path,before,after=defs[name];assert original[path].count(before)==1
  (work/path).write_text(original[path].replace(before,after,1))
  status=run(cmd,item/'mutant.log',env,cwd=work,timeout=120,required=False);record=json.loads((item/'mutant.log.json').read_text());text=(item/'mutant.log').read_text();killed=accepted(dict(name=name,test=test,baseline_green=baseline),text,record)
  rows.append(dict(name=name,test_target=target,test=test,needles=needles,baseline_green=baseline,mutation_killed=killed,source_sha256=sha(work/path),baseline=base,mutant=record))
  (ev/'summary.json').write_text(json.dumps(dict(combined_source=identity,rows=rows,accepted=len(rows)==16 and all(r['mutation_killed'] for r in rows)),indent=2)+'\n')
  print(name,baseline,killed,flush=True)
 return 0 if all(r['mutation_killed'] for r in rows) else 1
if __name__=='__main__':raise SystemExit(main())
