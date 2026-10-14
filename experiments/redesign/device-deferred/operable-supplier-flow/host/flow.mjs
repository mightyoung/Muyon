import {spawn, execFile} from 'node:child_process';
import {promisify, isDeepStrictEqual} from 'node:util';
import {readFile, mkdir, stat, lstat, open, rename} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {createHash, randomUUID} from 'node:crypto';
const exec = promisify(execFile);
const BINARY='/tmp/rd-p07-independent-target/debug/rd-p07-atomic';
const SHA='62232d1bdec9f923058dd9446b644781737caef9e111dc4dbb5658afe54c674c';
const DOMAIN='rd-p08-synthetic', SCOPE='fixture';
const ids=['S1','S2'];
const statuses=['editing','prepared','saving','saved','conflict','unknown','rejected','unavailable'];
const reasons=['RawLimit','InvalidXml','Required','NameLimit','Scope','Missing','Revision','RevisionOverflow','Operation'];
const revision=v=>typeof v==='string' && /^[1-9][0-9]{0,19}$/.test(v) && BigInt(v)<=18446744073709551615n;
const object=v=>v!==null && typeof v==='object' && !Array.isArray(v);
const exact=(v,keys)=>object(v) && Object.keys(v).sort().join(',')===[...keys].sort().join(',');
const units=s=>Array.from({length:s.length},(_,i)=>s.charCodeAt(i));
const bindingKeys=['domain','scope','supplier','intent','operation','raw_utf16','expected_revision','plan','candidate'];
const uuid=v=>typeof v==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(v);
export class FlowError extends Error { constructor(code) {super(code);this.code=code;} }
function demand(v,code='invalid_state') {if(!v) throw new FlowError(code);}
function validBinding(b,e) {
 return exact(b,bindingKeys) && b.domain===DOMAIN && b.scope===SCOPE && b.supplier===e.supplier && b.intent===e.intent && b.operation==='supplier.name' && b.expected_revision===e.expected_revision && uuid(b.plan) && uuid(b.candidate) && isDeepStrictEqual(b.raw_utf16,units(e.raw));
}
export function validateAction(a) {
 const fields={select:['supplier'],edit:[],draft:['raw'],preview:[],save:[],cancel:[],lookup:[]};
 demand(object(a)&&Object.hasOwn(fields,a.action)&&exact(a,['action',...fields[a.action]]),'invalid_action');
 if(a.action==='select') demand(ids.includes(a.supplier),'invalid_action');
 if(a.action==='draft') demand(typeof a.raw==='string'&&a.raw.length<=8192,'invalid_action');
 return a;
}
async function exists(p) {try {await lstat(p);return true;}catch(e) {if(e.code==='ENOENT')return false;throw e;}}
async function lock(dir) {
 const child=spawn('/usr/bin/flock',['-n',join(dir,'host.lock'),process.execPath,'-e',"process.stdout.write('locked\\n');process.stdin.resume()"],{stdio:['pipe','pipe','pipe']});
 await new Promise((yes,no)=>{child.once('error',no);child.once('exit',()=>no(new FlowError('host_already_running')));child.stdout.once('data',()=>yes());});
 return child;
}
export class Flow {
 static async open({dir}) {
  demand(typeof dir==='string');dir=resolve(dir);await mkdir(dir,{recursive:true,mode:0o700});const info=await lstat(dir);demand(info.isDirectory()&&!info.isSymbolicLink()&&(info.mode&0o077)===0,'unsafe_directory');
  demand(createHash('sha256').update(await readFile(BINARY)).digest('hex')===SHA,'binary_mismatch');
  const f=new Flow(dir);f.lock=await lock(dir);f.lock.once('exit',()=>{f.poisoned=true;});
  try {
   const journal=await exists(f.file),db=await exists(f.db);demand(journal===db,'incomplete_storage');
   if(!journal) {await f.call({op:'init',domain:DOMAIN,scope:SCOPE,supplier:'S1'});f.data={version:1,sessions:{}};await f.persist();}
   else {demand((await stat(f.file)).size<=4*1024*1024,'journal_corrupt');f.data=JSON.parse(await readFile(f.file,'utf8'));f.validateJournal();}
   for(const s of Object.values(f.data.sessions)) if(s.editor?.dispatched) {s.editor.status='unknown';s.editor.receipt=null;await f.resolve(s.editor);}
   await f.persist();return f;
  } catch(e) {await f.close();throw e;}
 }
 constructor(dir) {this.dir=dir;this.db=join(dir,'business.sqlite');this.file=join(dir,'sessions.json');this.queue=Promise.resolve();this.closed=false;this.poisoned=false;}
 validateJournal() {
  const d=this.data;demand(exact(d,['version','sessions'])&&d.version===1&&object(d.sessions)&&Object.keys(d.sessions).length<=32,'journal_corrupt');
  for(const [key,s] of Object.entries(d.sessions)) {
   demand(uuid(key)&&exact(s,['selected','editor'])&&(s.selected===null||ids.includes(s.selected)),'journal_corrupt');
   const e=s.editor;if(e===null)continue;
   demand(exact(e,['intent','supplier','raw','status','expected_revision','preview','receipt','reason','binding','dispatched'])&&uuid(e.intent)&&ids.includes(e.supplier)&&typeof e.raw==='string'&&e.raw.length<=8192&&statuses.includes(e.status)&&revision(e.expected_revision)&&typeof e.dispatched==='boolean','journal_corrupt');
   demand(e.binding===null?!e.dispatched:validBinding(e.binding,e),'journal_corrupt');
   demand(e.preview===null||(exact(e.preview,['normalized_name','candidate_revision'])&&typeof e.preview.normalized_name==='string'&&revision(e.preview.candidate_revision)),'journal_corrupt');
   demand(e.reason===null||typeof e.reason==='string','journal_corrupt');
   demand(!['saving','saved','unknown'].includes(e.status)||e.dispatched,'journal_corrupt');
   demand(e.status!=='prepared'||(e.binding!==null&&e.preview!==null&&!e.dispatched),'journal_corrupt');
   if(e.receipt!==null)demand(e.dispatched&&this.validReceipt(e.receipt,e.binding),'journal_corrupt');
  }
 }
 async call(request) {
  const {stdout}=await exec(BINARY,['--db',this.db,'--request',JSON.stringify(request)],{timeout:10000,maxBuffer:256*1024,encoding:'utf8',shell:false});
  return JSON.parse(stdout);
 }
 async persist() {
  try {const temp=join(this.dir,`journal-${randomUUID()}.tmp`);const file=await open(temp,'wx',0o600);try {await file.writeFile(JSON.stringify(this.data));await file.sync();}finally {await file.close();}await rename(temp,this.file);const directory=await open(this.dir,'r');try {await directory.sync();}finally {await directory.close();}}
  catch(e) {this.poisoned=true;throw new FlowError('storage_unavailable');}
 }
 serial(fn) {const next=this.queue.then(()=>{demand(!this.closed&&!this.poisoned,'host_unavailable');return fn();});this.queue=next.catch(()=>{});return next;}
 async createSession() {return this.serial(async()=>{demand(Object.keys(this.data.sessions).length<32,'session_limit');const id=randomUUID();this.data.sessions[id]={selected:null,editor:null};await this.persist();return id;});}
 session(id) {demand(typeof id==='string'&&Object.hasOwn(this.data.sessions,id),'unknown_session');return this.data.sessions[id];}
 async row(id) {const r=await this.call({op:'read',domain:DOMAIN,scope:SCOPE,supplier:id});demand(exact(r,['status','supplier'])&&r.status==='read'&&exact(r.supplier,['id','name','revision'])&&r.supplier.id===id&&typeof r.supplier.name==='string'&&revision(r.supplier.revision),'invalid_reply');return {supplier:id,name:r.supplier.name,revision:r.supplier.revision};}
 async projection(id) {
  const s=this.session(id);const suppliers=[];for(const id of ids) {try{suppliers.push(await this.row(id));}catch{}}
  const current=s.editor?suppliers.find(r=>r.supplier===s.editor.supplier)??null:null;
  const editor=s.editor?Object.fromEntries(['intent','supplier','raw','status','expected_revision','preview','receipt','reason'].map(k=>[k,s.editor[k]])):null;
  if(editor)editor.current=current;
  return structuredClone({suppliers,selected:suppliers.find(r=>r.supplier===s.selected)??null,editor,capability:'合成实验可信本机能力；正式授权未接线。M03 blocked_contract。列表为独立读取，非原子快照。',session:id,list_status:suppliers.length===2?'available':suppliers.length?'partial':'unavailable',recoverable_sessions:Object.entries(this.data.sessions).map(([session,s])=>({session,supplier:s.editor?.supplier??null,status:s.editor?.status??null}))});
 }
 async state(id) {return this.serial(()=>this.projection(id));}
 validReceipt(r,b) {
  return exact(r,['intent','binding','binding_sha256','source','supplier','old_name','new_name','old_revision','new_revision'])&&isDeepStrictEqual(r.binding,b)&&r.intent===b.intent&&r.source===b.domain&&r.supplier===b.supplier&&typeof r.binding_sha256==='string'&&/^[a-f0-9]{64}$/.test(r.binding_sha256)&&typeof r.old_name==='string'&&typeof r.new_name==='string'&&revision(r.old_revision)&&revision(r.new_revision)&&r.old_revision===b.expected_revision;
 }
 accept(e,r) {
  e.receipt=null;
  if(exact(r,['status','receipt'])&&r.status==='committed'&&this.validReceipt(r.receipt,e.binding)) {e.status='saved';e.receipt=r.receipt;e.reason=null;return;}
  if(exact(r,['status','reason'])&&r.status==='rejected'&&reasons.includes(r.reason)) {e.status=r.reason==='Revision'?'conflict':'rejected';e.reason=r.reason;return;}
  if(exact(r,['status'])&&r.status==='conflict') {e.status='unknown';e.reason='binding_conflict';return;}
  if((exact(r,['status'])||exact(r,['status','receipt_found'])&&r.receipt_found===false)&&r.status==='unknown') {e.status='unknown';e.reason='result_unknown';return;}
  throw new FlowError('invalid_reply');
 }
 async resolve(e) {try{this.accept(e,await this.call({op:'lookup',...e.binding}));}catch{e.status='unknown';e.receipt=null;e.reason='lookup_unavailable';}}
 async action(id,input) {validateAction(input);return this.serial(async()=>{
  const s=this.session(id),e=s.editor;const unresolved=e?.dispatched&&!['saved','conflict','rejected'].includes(e.status);
  switch(input.action) {
   case 'select':s.selected=input.supplier;break;
   case 'edit': {
    demand(e===null&&s.selected!==null);const row=await this.row(s.selected);
    s.editor={intent:randomUUID(),supplier:s.selected,raw:row.name,status:'editing',expected_revision:row.revision,preview:null,receipt:null,reason:null,binding:null,dispatched:false};break;
   }
   case 'cancel':demand(!unresolved);s.editor=null;break;
   case 'draft':demand(e&&!e.dispatched);e.raw=input.raw;e.status='editing';e.preview=null;e.binding=null;e.reason=null;break;
   case 'preview': {
    demand(e&&!e.dispatched);if(!e.binding)e.binding={domain:DOMAIN,scope:SCOPE,supplier:e.supplier,intent:e.intent,operation:'supplier.name',raw_utf16:units(e.raw),expected_revision:e.expected_revision,plan:randomUUID(),candidate:randomUUID()};
    await this.persist();
    try {const r=await this.call({op:'preview',...e.binding});if(exact(r,['status','normalized_name','candidate_revision'])&&r.status==='preview'&&typeof r.normalized_name==='string'&&revision(r.candidate_revision)){e.status='prepared';e.preview={normalized_name:r.normalized_name,candidate_revision:r.candidate_revision};e.reason=null;}else if(exact(r,['status','reason'])&&r.status==='rejected'&&reasons.includes(r.reason)){e.status=r.reason==='Revision'?'conflict':'rejected';e.preview=null;e.reason=r.reason;}else throw new Error();}
    catch{e.status='unavailable';e.preview=null;e.reason='preview_unavailable';}break;
   }
   case 'save': {
    demand(e);if(e.dispatched)break;demand(e.status==='prepared'&&validBinding(e.binding,e));e.dispatched=true;e.status='saving';await this.persist();
    try {this.accept(e,await this.call({op:'commit',...e.binding}));}catch{e.status='unknown';e.reason='commit_unavailable';e.receipt=null;}break;
   }
   case 'lookup':demand(e?.dispatched);await this.resolve(e);break;
  }
  await this.persist();return this.projection(id);
 });}
 async close() {if(this.closed)return;await this.queue;this.closed=true;if(this.lock){const child=this.lock;if(child.exitCode===null){const ended=new Promise(r=>child.once('exit',r));child.stdin.end();await ended;}}}
}
