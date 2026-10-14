import test from 'node:test';
import http from 'node:http';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Flow} from './flow.mjs';
import {startServer} from './server.mjs';
async function fixture(t){const dir=await mkdtemp(join(tmpdir(),'rd-p08-http-'));const flow=await Flow.open({dir});const host=await startServer({flow});t.after(async()=>{await host.close();await flow.close();});return {...host,dir,flow};}
async function state(url,session){const r=await fetch(url+'/api/state',{headers:session?{'X-RD-P08-Session':session}:{}});assert.equal(r.status,200);return r.json();}
async function action(url,s,body,overrides={}){return fetch(url+'/api/action',{method:'POST',headers:{Origin:url,'Content-Type':'application/json','X-RD-P08-Session':s.session,'X-RD-P08-CSRF':s.csrf,...overrides},body:typeof body==='string'?body:JSON.stringify(body)});}
test('HTTP independent sessions produce actual stale CAS; exact Host Origin nonce and envelope enforced',async t=>{
 const {url,dir}=await fixture(t);const a=await state(url),b=await state(url);assert.notEqual(a.session,b.session);
 for(const s of [a,b])for(const x of [{action:'select',supplier:'S1'},{action:'edit'},{action:'draft',raw:s===a?'A draft':'B commit'},{action:'preview'}])assert.equal((await action(url,s,x)).status,200);
 assert.equal((await (await action(url,b,{action:'save'})).json()).editor.status,'saved');const stale=await (await action(url,a,{action:'save'})).json();assert.equal(stale.editor.status,'conflict');assert.equal(stale.editor.raw,'A draft');
 for(const bad of [{Origin:'https://evil.invalid'},{'X-RD-P08-CSRF':'bad'},{'Content-Type':'text/plain'}])assert.equal((await action(url,a,{action:'edit'},bad)).status,403,JSON.stringify(bad));
 const badHost=await new Promise((yes,no)=>{const req=http.get(url+'/api/state',{headers:{Host:'evil.invalid'}},r=>{r.resume();yes(r.statusCode);});req.on('error',no);});assert.equal(badHost,403);
 for(const body of ['{"action":"edit","action":"save"}',{action:'edit',db:'/tmp/wrong'},{action:'draft',raw:9},{action:'fault'},{action:'select',supplier:'S3'}])assert.equal((await action(url,a,body)).status,400);
 assert.equal((await action(url,a,' '.repeat(32769))).status,413);
 assert.equal((await fetch(url+'/api/state',{headers:{'X-RD-P08-Session':'missing'}})).status,409);
 const counts=JSON.parse(execFileSync('python3',['-c',"import sqlite3,json,sys; c=sqlite3.connect(sys.argv[1]); print(json.dumps([c.execute('select count(*) from history').fetchone()[0],c.execute('select count(*) from receipts').fetchone()[0]]))",join(dir,'business.sqlite')],{encoding:'utf8'}));assert.deepEqual(counts,[1,1]);
 for(const path of ['/../sessions.json','/%2e%2e/sessions.json','/host/flow.mjs','/api/action?fault=commit'])assert.equal((await fetch(url+path)).status,404);
});
