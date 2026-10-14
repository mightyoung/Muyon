import test from 'node:test';
import assert from 'node:assert/strict';
import {SupplierEditor,MemoryRustCorePort} from '../model.mjs';
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};
async function setup(){const port=new MemoryRustCorePort();const editor=new SupplierEditor(port);await editor.load();editor.edit();return {port,editor};}
test('load exposes a ready supplier',async()=>{const {editor}=await setup();assert.equal(editor.state.supplier.name,'示例供应商');});
test('raw reaches port without trim or NFC',async()=>{const {port,editor}=await setup();const raw='  e\u0301\u0001 ';editor.draft(raw);await editor.preview();assert.equal(port.lastRaw,raw);assert.equal(editor.state.validation,'invalid');});
test('double save same intent dispatches once and receipt drives success',async()=>{const {port,editor}=await setup();editor.draft('新名称');await editor.preview();const [a,b]=await Promise.all([editor.save(),editor.save()]);assert.equal(port.dispatches,1);assert.equal(editor.state.phase,'ready');assert.equal(a.id,b.id);assert.equal(editor.state.receipt.id,a.id);});
test('explicit same-name new intent gets independent receipt',async()=>{const {port,editor}=await setup();await editor.preview();const a=await editor.save();editor.edit();await editor.preview();const b=await editor.save();assert.notEqual(a.id,b.id);assert.equal(port.dispatches,2);assert.equal(b.revision,3);});
test('CAS conflict preserves exact draft',async()=>{const {port,editor}=await setup();editor.draft('  未保存  ');await editor.preview();port.record.revision++;await editor.save();assert.equal(editor.state.phase,'conflict');assert.equal(editor.state.raw,'  未保存  ');assert.equal(editor.state.receipt,null);});
test('unknown cannot dispatch or quietly create new intent; lookup recovers receipt',async()=>{const {port,editor}=await setup();await editor.preview();port.loseResponse=true;await editor.save();assert.equal(editor.state.phase,'unknown');const id=editor.state.intent;editor.edit();await editor.save();assert.equal(editor.state.intent,id);assert.equal(port.dispatches,1);await editor.lookup();assert.equal(editor.state.phase,'ready');assert.equal(editor.state.receipt.intent,id);});
test('notFound cannot prove failure or authorize redispatch',async()=>{const {port,editor}=await setup();await editor.preview();port.loseResponse=true;await editor.save();port.receipts.clear();await editor.lookup();assert.equal(editor.state.phase,'unknown');await editor.save();assert.equal(port.dispatches,1);});
test('old epoch preview cannot overwrite current draft',async()=>{const {port,editor}=await setup();const d=deferred();port.preview=()=>d.promise;const pending=editor.preview();editor.edit();editor.draft('当前草稿');d.resolve({kind:'plan',normalized:'旧',id:'old'});await pending;assert.equal(editor.state.raw,'当前草稿');assert.equal(editor.state.plan,null);});
test('late receipt is accounted without overriding newer projection',async()=>{const {port,editor}=await setup();editor.draft('旧名');await editor.preview();const plan=editor.state.plan;const d=deferred();port.commit=()=>d.promise;const intent=editor.state.intent;const pending=editor.save();await editor.load();editor.isolateUnresolved();editor.draft('新草稿');d.resolve({kind:'receipt',id:'late',intent,planId:plan.id,expectedRevision:plan.expectedRevision,supplierId:'mock-supplier-0001',revision:2,name:'旧名'});await pending;assert.equal(editor.receiptLedger.get('late')?.name,'旧名');assert.equal(editor.state.raw,'新草稿');assert.equal(editor.state.receipt,null);});

test('foreign intent receipt cannot mark saved or enter ledger',async()=>{const {port,editor}=await setup();await editor.preview();port.commit=async()=>({kind:'receipt',id:'forged',intent:'other',supplierId:'mock-supplier-0001',revision:2,name:'错误'});await editor.save();assert.equal(editor.state.phase,'unknown');assert.equal(editor.receiptLedger.size,0);});
test('foreign supplier lookup receipt cannot resolve unknown',async()=>{const {port,editor}=await setup();await editor.preview();port.loseResponse=true;await editor.save();port.lookup=async()=>({kind:'receipt',id:'foreign',intent:editor.state.intent,supplierId:'other',revision:2,name:'错误'});await editor.lookup();assert.equal(editor.state.phase,'unknown');assert.equal(editor.receiptLedger.size,0);});

async function prepared(){const p=new MemoryRustCorePort();const e=new SupplierEditor(p);await e.load();e.edit();await e.preview();return {p,e};}
test('empty receipt reference must not claim mock saved',async()=>{const {p,e}=await prepared();p.commit=async()=>({kind:'receipt',id:'',intent:e.state.intent,supplierId:e.state.supplier.id,revision:2,name:'New'});await e.save();assert.equal(e.state.phase,'unknown');assert.equal(e.receiptLedger.size,0);});
test('reload cannot unlock fresh dispatch while original effect is unknown',async()=>{const {p,e}=await prepared();p.loseResponse=true;await e.save();const original=e.state.intent;assert.equal(e.state.phase,'unknown');await e.load();e.edit();await e.preview();await e.save();assert.equal(p.dispatches,1);assert.equal(e.state.intent,original);});
test('unreadable original lookup remains unknown with no dispatch',async()=>{const {p,e}=await prepared();p.loseResponse=true;await e.save();p.lookup=async()=>{throw Error('synthetic unreadable')};await e.lookup();await e.save();assert.equal(e.state.phase,'unknown');assert.equal(p.dispatches,1);});
test('negative receipt revision must not claim mock saved',async()=>{const {p,e}=await prepared();p.commit=async()=>({kind:'receipt',id:'bad',intent:e.state.intent,supplierId:e.state.supplier.id,revision:-1,name:'New'});await e.save();assert.equal(e.state.phase,'unknown');});
for(const [label,patch] of [
 ['whitespace reference',{id:' \t '}],['unchanged revision',{revision:1}],['skipped revision',{revision:3}],
 ['wrong expected revision',{expectedRevision:99}],['wrong plan reference',{planId:'other'}],['wrong committed name',{name:'other'}],
]) test(`reject ${label} before accounting`,async()=>{
 const {port,editor}=await setup();await editor.preview();const commit=port.commit.bind(port);
 port.commit=async plan=>({...await commit(plan),...patch});await editor.save();
 assert.equal(editor.state.phase,'unknown');assert.equal(editor.receiptLedger.size,0);
});
test('repeated reload preserves unresolved raw and original identity until verified lookup',async()=>{
 const {port,editor}=await setup();editor.draft('  待核草稿  ');await editor.preview();port.loseResponse=true;await editor.save();const intent=editor.state.intent;
 for(let n=0;n<2;n++){await editor.load();editor.edit();await editor.save();assert.equal(editor.state.phase,'unknown');assert.equal(editor.state.intent,intent);assert.equal(editor.state.raw,'  待核草稿  ');}
 assert.equal(port.dispatches,1);await editor.lookup();assert.equal(editor.state.phase,'ready');editor.edit();await editor.preview();await editor.save();assert.equal(port.dispatches,2);
});
test('snapshot navigation during submission cannot mint intent and completion unlocks only accounted state',async()=>{
 const {port,editor}=await setup();await editor.preview();const commit=port.commit.bind(port);const gate=deferred();
 port.commit=async plan=>{await gate.promise;return commit(plan);};const intent=editor.state.intent;const pending=editor.save();
 await editor.load();editor.edit();assert.equal(editor.state.intent,intent);const duplicate=editor.save();gate.resolve();await Promise.all([pending,duplicate]);
 assert.equal(port.dispatches,1);assert.equal(editor.receiptLedger.size,1);assert.equal(editor.state.receipt,null);assert.equal(editor.state.phase,'ready');
});
test('explicit isolated draft cannot dispatch until original receipt is reconciled',async()=>{
 const {port,editor}=await setup();editor.draft('原始草稿');await editor.preview();port.loseResponse=true;await editor.save();const original=editor.state.intent;
 editor.isolateUnresolved();editor.draft('隔离新草稿');const fresh=editor.state.intent;assert.notEqual(fresh,original);await editor.preview();await editor.save();
 assert.equal(port.dispatches,1);assert.equal(editor.state.unresolvedIntent,original);await editor.lookup();
 assert.equal(editor.state.intent,fresh);assert.equal(editor.state.raw,'隔离新草稿');assert.equal(editor.state.receipt,null);assert.equal(editor.receiptLedger.size,1);assert.equal(editor.state.unresolvedIntent,null);
});
for(const result of [null,{}, {kind:'receipt'}]) test(`malformed response ${JSON.stringify(result)} stays unresolved`,async()=>{
 const {port,editor}=await setup();await editor.preview();port.commit=async()=>result;await editor.save();await editor.load();editor.edit();assert.equal(editor.state.phase,'unknown');assert.equal(editor.receiptLedger.size,0);
});
