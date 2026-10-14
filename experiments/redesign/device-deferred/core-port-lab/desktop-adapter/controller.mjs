// Renderer-facing state controller only; every domain outcome is computed by Rust.
import {rawUtf16} from './codec.mjs';
export class DesktopSession {
 constructor(port){this.port=port;this.epoch=port.initialEpoch;this.generation=0;this.receipts=new Map();this.state={phase:'loading',snapshot:null,raw:'',intent:null,plan:null,receipt:null};this.command=null;this.unresolved=false;}
 async read(){const generation=++this.generation;const reply=await this.port.request('snapshot',{display_epoch:this.epoch});this.display(reply,generation);return reply;}
 display(reply,generation){
  if(generation!==this.generation||reply.display_epoch!==this.epoch||reply.display_admission!=='current')return;
  if(reply.snapshot)this.state={...this.state,snapshot:reply.snapshot};
  if(this.state.phase==='loading')this.state={...this.state,phase:'ready'};
 }
 async initialize(){const reply=await this.port.request('hello',{display_epoch:this.epoch});this.display(reply,this.generation);return reply;}
 edit(object_id,intent,raw){
  if(this.unresolved)return false;
  const supplier=this.state.snapshot?.suppliers.find(s=>s.id===object_id);if(!supplier)return false;
  ++this.generation;this.command=null;this.state={...this.state,phase:'draft',intent,object_id,raw,expected_revision:supplier.revision,plan:null,receipt:null};return true;
 }
 async preview(){
  if(this.state.phase!=='draft')return;
  const generation=this.generation;
  const request={display_epoch:this.epoch,object_id:this.state.object_id,intent:this.state.intent,expected_revision:this.state.expected_revision,raw_utf16:rawUtf16(this.state.raw)};
  const reply=await this.port.request('preview',request);
  if(generation!==this.generation)return reply;
  if(reply.kind==='prepared'){
   const p=reply.plan;
   if(p.intent!==request.intent||p.object_id!==request.object_id||p.expected_revision!==request.expected_revision)throw new Error('unbound actual plan');
   this.state={...this.state,plan:Object.freeze({...p})};this.command=Object.freeze({...request,raw_utf16:Object.freeze([...request.raw_utf16]),plan_id:p.id});
  }else this.state={...this.state,phase:reply.kind==='conflict'?'conflict':'rejected'};
  return reply;
 }
 bindReceipt(reply){
  if(reply.kind!=='committed')return;
  const r=reply.receipt,c=this.command,p=this.state.plan;
  if(!c||!p||r.intent!==c.intent||r.object_id!==c.object_id||r.expected_revision!==c.expected_revision||r.parameters_digest!==p.parameters_digest||r.normalized_name!==p.normalized_name)throw new Error('unbound actual receipt');
  this.receipts.set(r.id,r);this.unresolved=false;
 }
 async commit(){
  if(this.inFlight)return this.inFlight;
  if(this.state.phase==='ready'&&this.state.receipt)return this.state.receipt;
  if(!this.command||this.state.phase!=='draft')return;
  const generation=this.generation;this.unresolved=true;this.state={...this.state,phase:'submitting'};
  this.inFlight=(async()=>{
   let reply;try{reply=await this.port.request('commit',this.command);this.bindReceipt(reply);}catch{if(generation===this.generation)this.state={...this.state,phase:'unknown'};return {kind:'transport_unknown'};}
   if(reply.kind==='conflict'||reply.kind==='rejected')this.unresolved=false;
   this.display(reply,generation);
   if(generation===this.generation)this.state={...this.state,phase:reply.kind==='committed'?'ready':reply.kind==='conflict'?'conflict':reply.kind==='unknown'?'unknown':'rejected',receipt:reply.receipt};
   else if(this.state.phase==='submitting')this.state={...this.state,phase:this.unresolved?'unknown':'ready'};
   return reply;
  })();
  try{return await this.inFlight;}finally{this.inFlight=null;}
 }
 async lookup(){
  if(!this.command||this.state.phase!=='unknown'||this.inFlight)return;
  const generation=this.generation;
  const reply=await this.port.request('lookup',this.command);this.bindReceipt(reply);this.display(reply,generation);
  if(generation===this.generation&&reply.kind==='committed')this.state={...this.state,phase:'ready',receipt:reply.receipt};
  return reply;
 }
 async reconnect(newEpoch){
  const generation=++this.generation;const reply=await this.port.request('reconnect',{display_epoch:this.epoch,new_display_epoch:newEpoch});this.epoch=newEpoch;this.display(reply,generation);return reply;
 }
}
