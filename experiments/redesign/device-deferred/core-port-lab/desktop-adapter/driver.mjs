import {readFile,writeFile} from 'node:fs/promises';import {pathToFileURL} from 'node:url';
import {RustCoreProcess} from './port.mjs';
export async function runScenario(scenario){
 if(!scenario||typeof scenario.scenario_id!=='string'||!Array.isArray(scenario.steps))throw new Error('invalid scenario');
 const port=await RustCoreProcess.start(scenario.seed);const replies=[];
 try{
  for(const [index,step] of scenario.steps.entries()){
   if(!step.request||typeof step.request.op!=='string')throw new Error('missing actual request');
   const request=structuredClone(step.request);const {op}=request;delete request.op;
   if(Object.hasOwn(step,'plan_id_from')){
    const prior=step.plan_id_from;
    if(Object.hasOwn(request,'plan_id')||!Number.isInteger(prior)||prior<0||prior>=index||!replies[prior]?.plan)throw new Error('ambiguous/noncausal actual plan reference');
    request.plan_id=replies[prior].plan.id;
   }
   replies.push(await port.request(op,request,`step-${index}`));
  }
  return {scenario_id:scenario.scenario_id,replies};
 }finally{port.close();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const args=process.argv.slice(2);if(args.length!==4||args[0]!=='--input'||args[2]!=='--output')throw new Error('usage: --input trusted-fixture --output external-report');
 const scenario=JSON.parse(await readFile(args[1],'utf8'));const result=await runScenario(scenario);await writeFile(args[3],JSON.stringify(result,null,2)+'\n');
}
