// Test-only harness. Runtime server exposes no fault/barrier controls.
import {appendFile} from 'node:fs/promises';
import {join} from 'node:path';
import {Flow} from './flow.mjs';
import {startServer} from './server.mjs';
const [dir,mode]=process.argv.slice(2);
const original=Flow.prototype.call;
Flow.prototype.call=async function(request){
 await appendFile(join(dir,'request-trace.jsonl'),JSON.stringify(request)+'\n');
 const reply=await original.call(this,request);
 if(mode==='hold-after-commit'&&request.op==='commit') {
  process.send({event:'committed',reply});
  await new Promise(()=>{});
 }
 return reply;
};
try {const flow=await Flow.open({dir});const host=await startServer({flow});process.send({event:'ready',url:host.url});}
catch(e){process.send({event:'failed',reason:e.message});process.exit(1);}
