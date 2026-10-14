import test from 'node:test';
import assert from 'node:assert/strict';
import {fork,execFileSync} from 'node:child_process';
import {mkdtemp,readFile,writeFile,rename} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {Flow} from './flow.mjs';
const worker=new URL('./process-worker.mjs',import.meta.url);
function message(child,event){return new Promise((yes,no)=>{const timer=setTimeout(()=>no(new Error('worker timeout '+event)),10000);const receive=m=>{if(m.event===event){clearTimeout(timer);child.off('message',receive);yes(m);}else if(m.event==='failed'){clearTimeout(timer);no(new Error(m.reason));}};child.on('message',receive);});}
async function kill(child){if(child.exitCode!==null||child.signalCode!==null)return;const end=new Promise(r=>child.once('exit',r));child.kill('SIGKILL');await end;}
const physical=dir=>JSON.parse(execFileSync('python3',['-c',`import sqlite3,json,sys
c=sqlite3.connect(sys.argv[1]);print(json.dumps([c.execute('select revision from suppliers where id=?',('S1',)).fetchone()[0],c.execute('select count(*) from history').fetchone()[0],c.execute('select count(*) from receipts').fetchone()[0]]))`,join(dir,'business.sqlite')],{encoding:'utf8'}));
test('actual host SIGKILL after actual committed effect restores full original binding by lookup only',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'rd-p08-kill-'));const child=fork(worker,[dir,'hold-after-commit'],{stdio:['ignore','ignore','inherit','ipc']});t.after(()=>kill(child));const {url}=await message(child,'ready');
 let state=await (await fetch(url+'/api/state')).json();
 const act=async body=>{const r=await fetch(url+'/api/action',{method:'POST',headers:{Origin:url,'Content-Type':'application/json','X-RD-P08-Session':state.session,'X-RD-P08-CSRF':state.csrf},body:JSON.stringify(body)});assert.equal(r.status,200);return r.json();};
 for(const a of [{action:'select',supplier:'S1'},{action:'edit'},{action:'draft',raw:'  process restart  '},{action:'preview'}])state=await act(a);
 const committed=message(child,'committed');const lost=act({action:'save'}).catch(()=>null);const {reply}=await committed;
 const journal=JSON.parse(await readFile(join(dir,'sessions.json')));const original=journal.sessions[state.session].editor;
 assert.equal(original.status,'saving');assert.equal(original.dispatched,true);assert.deepEqual(original.binding,reply.receipt.binding);assert.deepEqual(physical(dir),['2',1,1]);
 await kill(child);assert.equal(await lost,null);execFileSync('/usr/bin/flock',['-w','5',join(dir,'host.lock'),'true']);
 const before=(await readFile(join(dir,'request-trace.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);assert.equal(before.filter(r=>r.op==='commit').length,1);
 const recovered=fork(worker,[dir,'normal'],{stdio:['ignore','ignore','inherit','ipc']});t.after(()=>kill(recovered));const next=await message(recovered,'ready');
 const restored=await (await fetch(next.url+'/api/state',{headers:{'X-RD-P08-Session':state.session}})).json();
 assert.equal(restored.editor.status,'saved');assert.equal(restored.editor.intent,original.intent);assert.equal(restored.editor.raw,original.raw);assert.deepEqual(restored.editor.receipt,reply.receipt);assert.notEqual(restored.csrf,state.csrf);
 const trace=(await readFile(join(dir,'request-trace.jsonl'),'utf8')).trim().split('\n').map(JSON.parse).slice(before.length);
 assert.equal(trace.filter(r=>r.op==='commit').length,0);assert.deepEqual(trace.find(r=>r.op==='lookup'),{op:'lookup',...original.binding});assert.deepEqual(physical(dir),['2',1,1]);
 const oldNonce=await fetch(next.url+'/api/action',{method:'POST',headers:{Origin:next.url,'Content-Type':'application/json','X-RD-P08-Session':state.session,'X-RD-P08-CSRF':state.csrf},body:'{"action":"save"}'});assert.equal(oldNonce.status,403);
});
test('lookup unavailable and altered original binding remain unknown; historical receipt stays separate from current row',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'rd-p08-lookup-'));let f=await Flow.open({dir});t.after(()=>f.close());const a=await f.createSession(),b=await f.createSession();
 async function save(s,raw){for(const x of [{action:'select',supplier:'S1'},{action:'edit'},{action:'draft',raw},{action:'preview'},{action:'save'}])await f.action(s,x);return f.state(s);}
 const first=await save(a,'first');await save(b,'later');const current=await f.state(a);assert.equal(current.editor.receipt.new_name,'first');assert.equal(current.editor.current.name,'later');assert.deepEqual(physical(dir),['3',2,2]);
 await rename(join(dir,'business.sqlite'),join(dir,'preserved.sqlite'));const unknown=await f.action(a,{action:'lookup'});assert.equal(unknown.editor.status,'unknown');assert.equal(unknown.editor.receipt,null);assert.equal(unknown.list_status,'unavailable');await rename(join(dir,'preserved.sqlite'),join(dir,'business.sqlite'));
 assert.deepEqual((await f.action(a,{action:'lookup'})).editor.receipt,first.editor.receipt);await f.close();
 const path=join(dir,'sessions.json');const j=JSON.parse(await readFile(path));j.sessions[a].editor.binding.plan='11111111-1111-4111-8111-111111111111';j.sessions[a].editor.receipt=null;j.sessions[a].editor.status='unknown';await writeFile(path,JSON.stringify(j));
 f=await Flow.open({dir});const altered=await f.state(a);assert.equal(altered.editor.status,'unknown');assert.equal(altered.editor.reason,'binding_conflict');assert.equal(altered.editor.intent,first.editor.intent);assert.deepEqual(physical(dir),['3',2,2]);
});
