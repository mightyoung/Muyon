import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {runScenario} from '../driver.mjs';
for(const name of ['baseline','lost-reply','stale-receipt'])test(`input-only ${name} observations come from actual fresh Rust process`,async()=>{
 const scenario=JSON.parse(await readFile(new URL(`../../fixtures/scenario-${name}.json`,import.meta.url),'utf8'));const out=await runScenario(scenario);
 assert.deepEqual(Object.keys(out),['scenario_id','replies']);assert.equal(out.replies.length,scenario.steps.length);for(const [i,r] of out.replies.entries())assert.equal(r.request_id,`step-${i}`);
 assert.equal(out.replies[0].kind,'hello');
});
test('driver rejects explicit plan plus reference rather than inventing expected plan',async()=>{await assert.rejects(runScenario({scenario_id:'bad',seed:'baseline',steps:[{request:{op:'hello',plan_id:'explicit'},plan_id_from:0}]}),/ambiguous/);});
test('driver rejects future/non-plan causal reference',async()=>{await assert.rejects(runScenario({scenario_id:'bad',seed:'baseline',steps:[{request:{op:'hello'}},{request:{op:'commit'},plan_id_from:0}]}),/causal/);});
