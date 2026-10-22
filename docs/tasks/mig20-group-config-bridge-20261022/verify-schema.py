#!/usr/bin/env python3
"""Check published v1 wire schemas using the preinstalled validator; no install."""
import copy, importlib.metadata, json, pathlib
from jsonschema import Draft202012Validator
base=pathlib.Path(__file__).resolve().parent
read=json.loads((base/'read-request.schema.json').read_text())
prepare=json.loads((base/'prepare-configuration.schema.json').read_text())
for schema in [read,prepare]: Draft202012Validator.check_schema(schema)
r=Draft202012Validator(read); p=Draft202012Validator(prepare)
requests=[{'operation':'catalog'},{'operation':'groups','limit':20,'after_group_id':None},{'operation':'group','group_id':'group'},{'operation':'runs','group_id':'group','limit':20}]+[{'operation':op,'group_id':'group',key:'original'} for op,key in [('run','run_id'),('workflow','run_id'),('local_intent','intent_id')]]
valid=[(r,{'schema_version':1,'request':q}) for q in requests]
registration={'schema_version':1,'change':{'operation':'register','intent_id':'create-group','group_id':'group','expected_revision':'0','members':{'a':{'scopes':['project'],'permissions':['read']}}}}
configuration=copy.deepcopy(registration);configuration['change'].update(operation='configure',expected_revision='2',mode='fixed',fixed_leader='a')
valid += [(p,registration),(p,configuration)]
invalid=[]
for v,raw in valid:
 q=copy.deepcopy(raw); q['schema_version']=2;invalid.append((v,q))
 q=copy.deepcopy(raw); q['workspace_id']='caller-ws';invalid.append((v,q))
q=copy.deepcopy(configuration); del q['change']['mode'];invalid.append((p,q))
q=copy.deepcopy(configuration);q['change']['mode']='automatic';invalid.append((p,q))
q={'schema_version':1,'request':{'operation':'groups','limit':51}};invalid.append((r,q))
for v,raw in valid: assert v.is_valid(raw),list(v.iter_errors(raw))
for v,raw in invalid: assert not v.is_valid(raw),raw
print(json.dumps({'validator':'jsonschema','version':importlib.metadata.version('jsonschema'),'valid_examples':len(valid),'invalid_examples':len(invalid),'result':'PASS','semantic_checks':'Native tests additionally cover duplicate keys, u64 upper bound, project/member/mode/authority context; schema cannot authenticate.'},indent=2))
