"""Exact semantic legacy inverse contract, retained from reviewed batch3 evidence."""
import re, hashlib
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
