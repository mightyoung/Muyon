import {spawn} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {FRAME_LIMIT,ReplyFrames,validateReply} from './codec.mjs';
export const TRUSTED_BINARY='/tmp/rd-p05-core-target/debug/rd-p05-core';
const CONSTRUCTION=Symbol('trusted-construction');
const SEEDS={baseline:'seed.json','lost-reply':'seed-lost-reply.json'};
export class RustCoreProcess {
 static async start(seed='baseline'){
  if(!Object.hasOwn(SEEDS,seed))throw new Error('unknown trusted seed');
  const path=fileURLToPath(new URL(`../fixtures/${SEEDS[seed]}`,import.meta.url));
  const fixture=JSON.parse(await readFile(path,'utf8'));
  return new RustCoreProcess(CONSTRUCTION,path,fixture.domain,fixture.display_epoch);
 }
 constructor(token,seedPath,domain,epoch){
  if(token!==CONSTRUCTION)throw new Error('trusted factory required');
  this.domain=Object.freeze({...domain});this.initialEpoch=epoch;this.sequence=0;this.pending=new Map();this.failed=false;this.decoder=new ReplyFrames();
  this.child=spawn(TRUSTED_BINARY,['--seed',seedPath],{shell:false,stdio:['pipe','pipe','pipe'],env:{LANG:'C.UTF-8'}});
  this.child.stdout.on('data',bytes=>{try{for(const reply of this.decoder.push(bytes)){
   const entry=this.pending.get(reply.request_id)??(reply.request_id===''&&reply.kind==='rejected'&&reply.reason==='invalid_request'&&this.pending.size===1?[...this.pending.values()][0]:null);if(!entry)throw new Error('unexpected/duplicate request id');
   const validated=validateReply(reply,entry.meta);clearTimeout(entry.timer);this.pending.delete(entry.meta.request_id);entry.resolve(validated);
  }}catch{this.fail('invalid or unbound core reply');}});
  this.child.stdout.on('end',()=>{try{this.decoder.finish();}catch{this.fail('truncated core reply');}this.fail('core EOF');});
  this.child.stderr.on('data',()=>{}); // Do not project possible diagnostic/raw content.
  this.child.on('error',()=>this.fail('core unavailable'));this.child.on('exit',()=>this.fail('core exited'));
  this.child.stdin.on('error',()=>this.fail('core input unavailable'));
 }
 request(op,fields={},trustedId){
  if(this.failed)return Promise.reject(new Error('core unavailable'));
  if(this.pending.size>=16)return Promise.reject(new Error('bounded request queue full'));
  const request_id=trustedId??`node-${++this.sequence}`;
  const request={protocol:0,request_id,op,domain:this.domain,display_epoch:this.initialEpoch,...structuredClone(fields)};
  // Renderer cannot choose correlation/version. Negative domain/epoch cases remain Rust decisions.
  request.request_id=request_id;request.op=op;
  const bytes=Buffer.from(JSON.stringify(request));if(bytes.length>FRAME_LIMIT)return Promise.reject(new Error('request frame too large'));
  return new Promise((resolve,reject)=>{
   const timer=setTimeout(()=>this.fail('core response timeout'),5000);
   this.pending.set(request_id,{resolve,reject,timer,meta:{request_id,domain:this.domain,allowInvalid:true,display_epoch:op==='reconnect'?request.new_display_epoch:request.display_epoch}});
   this.child.stdin.write(Buffer.concat([bytes,Buffer.from('\n')]));
  });
 }
 fail(reason){
  if(this.failed)return;this.failed=true;
  for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(new Error(reason));}this.pending.clear();
  this.child.stdin.destroy();this.child.kill();
 }
 close(){this.fail('core closed');}
}
