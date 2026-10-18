"""Post-run source-line and exact semantic assertion review; keeps broad-run false positives separate."""
import sys,json,re,copy,hashlib
from pathlib import Path
E=Path('/workspace/leaderb-b3-evidence/b');ROOT=Path('/workspace/leaderb-b3-b')
sys.path.insert(0,str(ROOT/'experiments/redesign/rust-agent-host-lab/checks'))
from http_batch import inverse
EXPECTED={
'wire_stale_reported_usage':('wire.rs:182:306','left: "5"','right: "unknown"'),
'wire_private_history_bound':('wire.rs:88:180','error=wire_json_size'),
'wire_container_depth':('wire_review.rs:9:9','33 containers exceed the frozen limit'),
'wire_native_value_identity':('wire_review.rs:18:5','a paired ID cannot conceal changed original value'),
'wire_stream_cancel_bypass':('wire.rs:122:161','right: "wire_cancelled"'),
'wire_missing_done':('http_transport.rs:161:5','left: "wire_tool_finish"','right: "wire_stream_truncated"'),
'wire_native_pair':('wire.rs:173:1005','left: String("wrong-pair")','right: String("c1")'),
'wire_budget_bypass':('wire.rs:106:184','left: "1"','right: "0"'),
'hard_policy_bypass':('kernel.rs:15:5','left: Permit','right: Denied'),
'unknown_redispatch':('kernel.rs:104:5',r'assertion failed: command(&dir, "run", &[]).contains("model_calls=1\n")'),
'duplicate_effect':('kernel.rs:72:40','called `Result::unwrap()` on an `Err` value: "receipt_identity"'),
'pre_effect_context_bypass':('kernel.rs:170:96',r'assertion failed: stopped.contains("effects=0\n")'),

 'terminal_resurrection':('kernel.rs:140:5',r'assertion failed: command(&dir, "lookup", &[]).contains("status=completed\n")'),
'cached_receipt_trust':('kernel.rs:120:45',r'assertion failed: inspect.contains("status=outcome_unknown\n")'),
'receipt_current_binding_only':('kernel.rs:181:9',r'assertion failed: command(&dir, "inspect", &[]).contains("status=outcome_unknown\n")'),
'budget_reset':('kernel.rs:78:5','assertion `left == right` failed',r'\nmodel_calls=0\n',r'\nmodel_calls=1\n')}
def accepted(row,text,record):
 location,*needles=EXPECTED[row['name']]
 panics=re.findall(r"thread '([^']+)'[^\n]*panicked at ([^\n]+):\n",text)
 return hashlib.sha256(text.encode()).hexdigest()==record['raw_sha256'] and row['baseline_green'] and panics==[(row['test'],'tests/'+location)] and inverse(text,record,row['test'],needles)
def main():
 raw=json.loads((E/'legacy17-exact/summary.json').read_text());rows=[];controls=0
 for row in raw['rows']:
  text=(E/'legacy17-exact'/row['name']/'mutant.log').read_text();record=row['mutant']
  baseline=(E/'legacy17-exact'/row['name']/'baseline.log').read_bytes()
  assert hashlib.sha256(baseline).hexdigest()==row['baseline']['raw_sha256']
  good=accepted(row,text,record)
  assert good,row['name']
  for key,value in [('exit_code',0),('exit_code',124),('timed_out',True),('forced_owned_group_cleanup',True),('live_after_cleanup',[1])]:
   bad=dict(record,**{key:value});assert not accepted(row,text,bad);controls+=1
  location,*needles=EXPECTED[row['name']]
  for bad in ['could not compile\n'+text,text.replace('tests/'+location,'tests/wrong.rs:1:1'),text.replace(row['test'],'wrong_target'),text.replace(needles[0],'WRONG_ASSERTION')]:
   changed=dict(record,raw_sha256=hashlib.sha256(bad.encode()).hexdigest())
   assert not accepted(row,bad,changed);controls+=1
  rows.append(dict(name=row['name'],accepted=good,expected_panic_location='tests/'+location,expected_needles=needles))
 physical=json.loads((E/'legacy17-combined/summary.json').read_text())[-1]
 physical_good=physical['name']=='wire_preterminal_physical_effect' and physical['compiled'] and physical['returncode']==1 and physical['acknowledged'] and physical['physical_failure']
 physical_raw=Path(physical['log']).read_text();build_raw=Path(physical['build_log']).read_text()
 physical_good=physical_good and 'RUST_WIRE_ARGS_ACK_OBSERVED' in physical_raw and 'FAILED (failures=1)' in physical_raw and re.search(r'AssertionError: 1 != 0[^\n]*PRETERMINAL_(?:PHYSICAL_EFFECT|CONFIRMATION_CONSUMED)',physical_raw) is not None and 'MUTANT_SETUP_' not in physical_raw and re.search(r'Finished [^\n]*dev[^\n]*profile',build_raw) is not None
 result=dict(physical_raw_sha256=hashlib.sha256(physical_raw.encode()).hexdigest(),physical_build_raw_sha256=hashlib.sha256(build_raw.encode()).hexdigest(),source_sha=raw['combined_source']['source_sha'],accepted=len(rows)==16 and all(r['accepted'] for r in rows) and physical_good,precise_rust16=rows,physical17=physical,negative_control_checks=controls,broad_runner_false_positive='wire_container_depth failed only at unrelated PID capture and did not reach wire_review; broad KILLED label is rejected. Precise rerun is authoritative.')
 (E/'legacy17-semantic-audit.json').write_text(json.dumps(result,indent=2)+'\n');print(result['accepted'],controls)
 return 0 if result['accepted'] else 1
if __name__=='__main__':raise SystemExit(main())
