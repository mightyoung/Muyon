"""Causal fsync-latency experiment; does not replace the physical acceptance gate.

Each injected fsync still calls the real syscall. Existing 5000ms exchange and
2000ms idle budgets, response bytes and process invocation are retained.
"""
import argparse,hashlib,json,os,pathlib,subprocess,time
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary',type=pathlib.Path,required=True)
parser.add_argument('--evidence-dir',type=pathlib.Path,required=True)
args=parser.parse_args()
lab=pathlib.Path(__file__).resolve().parents[2]
evidence=args.evidence_dir.resolve()
assert not evidence.is_relative_to(lab), 'evidence must be external'
evidence.mkdir(parents=True,exist_ok=True)
binary=args.binary.resolve(strict=True)
shim=pathlib.Path(__file__).with_name('timing_fsync_delay.c')
subprocess.run(['cc','-shared','-fPIC','-o',str(evidence/'fsync_delay.so'),str(shim),'-ldl'],check=True)
identity={'source_sha':subprocess.check_output(['git','-C',str(lab),'rev-parse','HEAD'],text=True).strip(),
          'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
          'shim_sha256':hashlib.sha256(shim.read_bytes()).hexdigest()}
(evidence/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
records=[]
for delayed in (False,True):
 for chunk in (8192,1,7):
  case=f'io-delay-{int(delayed)}-chunk-{chunk}'
  directory=evidence/case
  start=[str(binary),'start','--dir',str(directory),'--provider','chat-sse','--wire-helper',str(lab/'fixtures/wire/fake_service.py'),'--wire-fixtures',str(lab/'fixtures/wire/scenarios/escaped-pair'),'--input','synthetic wire input','--mode','full-allow','--wire-chunk-size',str(chunk),'--wire-total-ms','5000','--wire-idle-ms','2000']
  subprocess.run(start,check=True,capture_output=True)
  env=dict(os.environ)
  if delayed:env['LD_PRELOAD']=str(evidence/'fsync_delay.so')
  t=time.monotonic();result=subprocess.run([str(binary),'run','--dir',str(directory)],env=env,text=True,capture_output=True,timeout=20)
  elapsed=time.monotonic()-t
  (evidence/(case+'.log')).write_text(result.stdout+result.stderr)
  values=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
  assert int(values['wire_total_bytes']) == int(values['wire_sent_bytes'])+int(values['wire_received_bytes'])
  for pid_file in (directory/'wire-capture').glob('child-*.pid'):
   assert not pathlib.Path('/proc/'+pid_file.read_text().strip()).exists(), 'helper was not reaped'
  if values['status']=='completed':
   assert values['effects']=='1'
   assert bytes.fromhex(values['value_hex']).decode()=='😀'
   assert json.loads(bytes.fromhex(values['answer_hex']))=={'receipt':'r-i-1','value':'😀'}
  else:
   before={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (directory/'wire-capture').iterdir()}
   reopened=subprocess.run([str(binary),'run','--dir',str(directory)],check=True,text=True,capture_output=True)
   assert reopened.stdout==result.stdout, 'timeout state changed on reopen'
   assert before=={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (directory/'wire-capture').iterdir()}, 'timeout resent request'
  records.append(dict(case=case,exit=result.returncode,elapsed=elapsed,fields=values))
  print(json.dumps(records[-1]),flush=True)
(evidence/'controlled-io.json').write_text(json.dumps(records,indent=2)+'\n')
assert all(r['exit']==0 for r in records)
assert [r['fields']['status'] for r in records]==['completed','completed','completed','completed','failed','completed']
assert records[4]['fields']['reason']=='wire_total_timeout'
assert records[4]['fields']['effects']=='0'
assert 0 < int(records[4]['fields']['wire_received_bytes']) < 377
assert (evidence/'io-delay-1-chunk-1/wire-capture/emitted-1.sse').stat().st_size == 377
