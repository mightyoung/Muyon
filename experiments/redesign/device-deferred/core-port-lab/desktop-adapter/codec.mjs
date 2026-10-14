// Transport codec only. Domain normalization, CAS and receipt authority are Rust-owned.
export const FRAME_LIMIT=32768;
const COUNTER_MAX='18446744073709551615';
export function rawUtf16(raw){
 if(typeof raw!=='string')throw new TypeError('raw must be string');
 return Array.from({length:raw.length},(_,i)=>raw.charCodeAt(i));
}
export function decimal(value){
 if(typeof value!=='string'||!/^(0|[1-9][0-9]*)$/.test(value)||value.length>20||(value.length===20&&value>COUNTER_MAX))throw new Error('invalid decimal u64');
 return value;
}
function fields(value,names){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length!==names.length||names.some(k=>!Object.hasOwn(value,k)))throw new Error('invalid response shape');
}
function text(value){if(typeof value!=='string')throw new Error('invalid text');}
function identifier(value){text(value);if(!value.length||Buffer.byteLength(value)>128)throw new Error('invalid identifier');}
function domain(value){fields(value,['store','scope','stream']);for(const s of Object.values(value))identifier(s);}
export function sameDomain(a,b){return ['store','scope','stream'].every(k=>a[k]===b[k]);}
function cursor(value,expected){fields(value,['store','scope','stream','seq']);domain({store:value.store,scope:value.scope,stream:value.stream});decimal(value.seq);if(!sameDomain(value,expected))throw new Error('foreign cursor domain');}
export function validateReply(reply,meta){
 fields(reply,['protocol','request_id','kind','reason','domain','display_epoch','display_admission','snapshot','plan','receipt']);
 const invalid=meta.allowInvalid&&reply.kind==='rejected'&&reply.reason==='invalid_request'&&reply.request_id===''&&reply.display_epoch===''&&reply.snapshot===null&&reply.plan===null&&reply.receipt===null;
 if(reply.protocol!==0||(!invalid&&(reply.request_id!==meta.request_id||reply.display_epoch!==meta.display_epoch)))throw new Error('reply correlation mismatch');
 if(!invalid){identifier(reply.request_id);identifier(reply.display_epoch);}domain(reply.domain);
 if(!sameDomain(reply.domain,meta.domain)||!['current','stale'].includes(reply.display_admission))throw new Error('reply domain/admission mismatch');
 if(!['hello','snapshot','prepared','committed','conflict','rejected','unknown'].includes(reply.kind))throw new Error('invalid reply kind');
 if(reply.reason!==null)text(reply.reason);
 if(reply.snapshot!==null){
  fields(reply.snapshot,['cursor','suppliers']);cursor(reply.snapshot.cursor,meta.domain);if(!Array.isArray(reply.snapshot.suppliers))throw new Error('invalid suppliers');
  const ids=new Set();for(const s of reply.snapshot.suppliers){fields(s,['id','name','revision']);identifier(s.id);text(s.name);decimal(s.revision);if(ids.has(s.id))throw new Error('duplicate supplier');ids.add(s.id);}
 }
 if(reply.plan!==null){const p=reply.plan;fields(p,['id','intent','object_id','expected_revision','normalized_name','parameters_digest']);for(const k of ['id','intent','object_id','parameters_digest'])identifier(p[k]);decimal(p.expected_revision);text(p.normalized_name);}
 if(reply.receipt!==null){const r=reply.receipt;fields(r,['kind','id','intent','object_id','expected_revision','result_revision','normalized_name','parameters_digest','commit_cursor']);if(r.kind!=='synthetic')throw new Error('unexpected receipt kind');for(const k of ['id','intent','object_id','parameters_digest'])identifier(r[k]);decimal(r.expected_revision);decimal(r.result_revision);text(r.normalized_name);cursor(r.commit_cursor,meta.domain);}
 if(reply.kind==='prepared'&&(reply.plan===null||reply.receipt!==null))throw new Error('preview is not an effect');
 if(reply.kind==='committed'&&reply.receipt===null)throw new Error('missing actual receipt');
 if(['unknown','rejected','conflict'].includes(reply.kind)&&reply.receipt!==null)throw new Error('failure cannot claim receipt');
 if(['hello','snapshot'].includes(reply.kind)&&reply.snapshot===null)throw new Error('missing actual snapshot');
 return reply;
}
export class ReplyFrames {
 constructor(){this.tail=Buffer.alloc(0);}
 push(bytes){
  let buffer=Buffer.concat([this.tail,bytes]);const frames=[];
  for(;;){const end=buffer.indexOf(10);if(end<0)break;if(end>FRAME_LIMIT)throw new Error('oversize reply frame');if(end===0)throw new Error('empty reply frame');
   const line=new TextDecoder('utf-8',{fatal:true}).decode(buffer.subarray(0,end));frames.push(JSON.parse(line));buffer=buffer.subarray(end+1);
  }
  if(buffer.length>FRAME_LIMIT)throw new Error('oversize unfinished reply');this.tail=Buffer.from(buffer);return frames;
 }
 finish(){if(this.tail.length)throw new Error('truncated reply at EOF');return [];}
}
