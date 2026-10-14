import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {Flow} from './flow.mjs';
const inspect = dir => JSON.parse(execFileSync('python3',['-c',`import sqlite3,json,sys
c=sqlite3.connect(sys.argv[1]); print(json.dumps({'rows':c.execute('select id,name,revision from suppliers order by id').fetchall(),'history':c.execute('select count(*) from history').fetchone()[0],'receipts':c.execute('select count(*) from receipts').fetchone()[0]}))`,join(dir,'business.sqlite')],{encoding:'utf8'}));
async function fixture(t) {const dir=await mkdtemp(join(tmpdir(),'rd-p08-host-')); const flow=await Flow.open({dir});t.after(()=>flow.close());return {dir,flow,s:await flow.createSession()};}
async function prepare(flow,s,raw='  Cafe\u0301  ',supplier='S1') {await flow.action(s,{action:'select',supplier});await flow.action(s,{action:'edit'});await flow.action(s,{action:'draft',raw});return flow.action(s,{action:'preview'});}
test('actual P07 save preserves raw and restart recovers original receipt without another effect',async t=>{
 const {dir,flow,s}=await fixture(t);await prepare(flow,s); const saved=await flow.action(s,{action:'save'});
 assert.equal(saved.editor?.status,'saved');assert.equal(saved.editor.raw,'  Cafe\u0301  ');assert.equal(saved.editor.receipt.new_name,'Café');
 assert.equal(inspect(dir).history,1);await flow.close();const restored=await Flow.open({dir});t.after(()=>restored.close());
 assert.deepEqual((await restored.state(s)).editor.receipt,saved.editor.receipt);assert.equal(inspect(dir).receipts,1);
});
test('actual P07 stale CAS preserves draft and expected revision, same-name selection targets ID',async t=>{
 const {dir,flow,s}=await fixture(t);const other=await flow.createSession();await prepare(flow,s,'stale');await prepare(flow,other,'new current');await flow.action(other,{action:'save'});
 const conflict=await flow.action(s,{action:'save'});assert.equal(conflict.editor?.status,'conflict');assert.equal(conflict.editor.raw,'stale');assert.equal(conflict.editor.expected_revision,'1');assert.equal(conflict.editor.current.name,'new current');
 assert.deepEqual(inspect(dir).rows,[['S1','new current','2'],['S2','Before','1']]);
});
test('raw UTF16 stays exact; validation/previews never write; changed draft invalidates prepared binding',async t=>{
 const {dir,flow,s}=await fixture(t);
 for(const [raw,reason] of [['\ud800','InvalidXml'],['\u0001','InvalidXml'],[' '.repeat(4),'Required'],['x'.repeat(2001),'RawLimit']]) {
  await flow.action(s,{action:'select',supplier:'S2'});await flow.action(s,{action:'edit'});await flow.action(s,{action:'draft',raw});const p=await flow.action(s,{action:'preview'});
  assert.equal(p.editor.status,'rejected');assert.equal(p.editor.reason,reason);assert.equal(p.editor.raw,raw);assert.equal(inspect(dir).history,0);await flow.action(s,{action:'cancel'});
 }
 const p=await prepare(flow,s,'  S2 name  ','S2');assert.equal(inspect(dir).history,0);
 const before=JSON.parse(await readFile(join(dir,'sessions.json'))).sessions[s].editor.binding;
 await flow.action(s,{action:'draft',raw:'different'});await assert.rejects(flow.action(s,{action:'save'}));
 await flow.action(s,{action:'preview'});const after=JSON.parse(await readFile(join(dir,'sessions.json'))).sessions[s].editor.binding;
 assert.equal(before.intent,after.intent);assert.notEqual(before.plan,after.plan);assert.deepEqual(after.raw_utf16,[... 'different'].map(x=>x.charCodeAt(0)));
 const [a,b]=await Promise.all([flow.action(s,{action:'save'}),flow.action(s,{action:'save'})]);assert.deepEqual(a.editor.receipt,b.editor.receipt);assert.equal(inspect(dir).history,1);assert.deepEqual(inspect(dir).rows,[['S1','Before','1'],['S2','different','2']]);
});
test('unknown never rekeys or cancels; missing lookup stays unknown',async t=>{
 const {dir,flow,s}=await fixture(t);await prepare(flow,s);const original=flow.call.bind(flow);const calls=[];
 flow.call=async request=>{calls.push(request);if(request.op==='commit')throw new Error('test-owned transport loss before execution');return original(request);};
 const unknown=await flow.action(s,{action:'save'});assert.equal(unknown.editor.status,'unknown');
 for(const a of [{action:'cancel'},{action:'edit'},{action:'draft',raw:'replacement'}])await assert.rejects(flow.action(s,a));
 await flow.action(s,{action:'select',supplier:'S2'});assert.equal((await flow.state(s)).editor.intent,unknown.editor.intent);
 assert.equal((await flow.action(s,{action:'lookup'})).editor.status,'unknown');await flow.action(s,{action:'save'});assert.equal(calls.filter(x=>x.op==='commit').length,1);assert.equal(inspect(dir).history,0);
});
test('journal corruption, missing pairing and competing host fail closed',async t=>{
 const {dir,flow,s}=await fixture(t);await assert.rejects(Flow.open({dir}),/host_already_running/);await prepare(flow,s);await flow.close();
 const {writeFile,rename}=await import('node:fs/promises');const journal=join(dir,'sessions.json');const good=await readFile(journal);await writeFile(journal,'{bad');await assert.rejects(Flow.open({dir}));await writeFile(journal,good);
 const bad=JSON.parse(good);bad.sessions[s].editor.binding.raw_utf16=[65];await writeFile(journal,JSON.stringify(bad));await assert.rejects(Flow.open({dir}),/journal_corrupt/);await writeFile(journal,good);
 await rename(journal,join(dir,'preserved-journal.json'));await assert.rejects(Flow.open({dir}),/incomplete_storage/);assert.equal(inspect(dir).history,0);
});
test('malformed or unbound postdispatch reply remains unknown and actual receipt is recoverable',async t=>{
 const {dir,flow,s}=await fixture(t);await prepare(flow,s);const original=flow.call.bind(flow);flow.call=async request=>{const r=await original(request);if(request.op==='commit')return {...r,receipt:{...r.receipt,binding:{...r.receipt.binding,supplier:'S2'}}};return r;};
 assert.equal((await flow.action(s,{action:'save'})).editor.status,'unknown');assert.equal(inspect(dir).history,1);
 assert.equal((await flow.action(s,{action:'lookup'})).editor.status,'saved');assert.equal(inspect(dir).history,1);
});
test('a later unverifiable lookup clears the previously verified receipt and locks the original intent',async t=>{
 const {dir,flow,s}=await fixture(t);await prepare(flow,s);const saved=await flow.action(s,{action:'save'});
 // Private negative fixture only: remove the actual receipt to force P07 unknown.
 execFileSync('python3',['-c',"import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('delete from receipts where intent=?',(sys.argv[2],)); c.commit()",join(dir,'business.sqlite'),saved.editor.intent]);
 const missing=await flow.action(s,{action:'lookup'});assert.equal(missing.editor.status,'unknown');assert.equal(missing.editor.receipt,null);assert.equal(missing.editor.intent,saved.editor.intent);await assert.rejects(flow.action(s,{action:'cancel'}));assert.equal(inspect(dir).history,1);
});
test('real journal write failure before dispatch poisons the host and causes zero business effect',async t=>{
 const {dir,flow,s}=await fixture(t);await prepare(flow,s);const {rename,writeFile}=await import('node:fs/promises');const preserved=dir+'-preserved';await rename(dir,preserved);await writeFile(dir,'test-owned write blocker');
 await assert.rejects(flow.action(s,{action:'save'}),/storage_unavailable/);await assert.rejects(flow.action(s,{action:'save'}),/host_unavailable/);assert.equal(inspect(preserved).history,0);assert.equal(inspect(preserved).receipts,0);
});
