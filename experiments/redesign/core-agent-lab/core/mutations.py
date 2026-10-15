#!/usr/bin/env python3
"""Run compiled semantic inverse mutants in private copies using existing offline Cargo only."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--evidence-dir', type=Path, required=True)
args = parser.parse_args()
args.evidence_dir.mkdir(parents=True, exist_ok=True)
source = Path(__file__).resolve().parent
mutations = [
    ('wire_stream_cancel_bypass', 'src/agent.rs',
     'if self.agent.cancelled()?{Err("wire_cancelled".into())}else{Ok(())}',
     'if false && self.agent.cancelled()?{Err("wire_cancelled".into())}else{Ok(())}'),
    ('wire_missing_done', 'src/wire_sse.rs',
     '||!self.done{return Err("wire_stream_truncated".into());}',
     '||(false && !self.done){return Err("wire_stream_truncated".into());}'),
    ('wire_native_pair', 'src/wire_provider.rs',
     '("tool_call_id",string(call_ref))', '("tool_call_id",string("wrong-pair"))'),
    ('wire_budget_bypass', 'src/wire_provider.rs',
     'if bytes.len() as u64>control.remaining(){return Err("wire_total_limit".into());}',
     'if false && bytes.len() as u64>control.remaining(){return Err("wire_total_limit".into());}'),
    ('hard_policy_bypass', 'src/policy.rs',
     'if !hard_ok || mode == Mode::ReadOnly', 'if mode == Mode::ReadOnly'),
    ('unknown_redispatch', 'src/agent.rs',
     'if self.state.evidence_hold || self.state.unresolved{return Ok(());}',
     'if self.state.evidence_hold{return Ok(());} if self.state.unresolved { self.state.unresolved=false; self.state.status="ready".into(); self.state.position=0; self.state.correlations.clear(); }'),
    ('duplicate_effect', 'src/store.rs',
     'if let Some(r)=state.receipts.iter().find(|r|r.binding.invocation==b.invocation){if &r.binding!=b{return Err("binding_conflict".into());}return Ok(r.clone());}',
     ''),
    ('pre_effect_context_bypass', 'src/agent.rs',
     'if model::context_bytes(&self.state.context).saturating_add(result_bytes)>self.state.limits.context {',
     'if false && model::context_bytes(&self.state.context).saturating_add(result_bytes)>self.state.limits.context {'),
    ('terminal_resurrection', 'src/agent.rs',
     'else{self.state.stop(&resume_status,&resume_reason);}',
     'else{self.state.stop("ready","");}'),
    ('cached_receipt_trust', 'src/agent.rs',
     'if !state.evidence_hold {', 'if false && !state.evidence_hold {'),
    ('receipt_current_binding_only', 'src/agent.rs',
     'if !state.evidence_hold {',
     'if !state.evidence_hold && state.receipt_binding.as_ref()==state.binding.as_ref() {'),
    ('budget_reset', 'src/agent.rs',
     'let mut state=State::load(dir)?;',
     'let mut state=State::load(dir)?;state.counters=Counters::default();'),
]
results = []
for name, file, before, after in mutations:
    # Preserve all mutant trees and raw logs for inspection. No production mutation.
    work = Path(tempfile.mkdtemp(prefix='core-agent-mutation-'))
    crate = work / 'core'
    shutil.copytree(source, crate, ignore=shutil.ignore_patterns('target', '__pycache__'))
    path = crate / file
    text = path.read_text()
    if text.count(before) != 1:
        raise SystemExit(f'{name}: expected one exact mutation site, got {text.count(before)}')
    path.write_text(text.replace(before, after, 1))
    cmd = ['cargo', 'test', '--offline', '--locked', '--manifest-path', str(crate / 'Cargo.toml')]
    run = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    log = args.evidence_dir / f'{name}.log'
    log.write_text(run.stdout)
    compiled = 'Finished `test`' in run.stdout or 'Finished test' in run.stdout
    killed = run.returncode != 0 and compiled and 'test result: FAILED' in run.stdout
    first = next((line for line in run.stdout.splitlines() if line.startswith('test ') and line.endswith(' ... FAILED')), '')
    results.append(dict(name=name, killed=killed, returncode=run.returncode, compiled=compiled, first_failure=first, log=str(log), crate=str(crate)))
    print(f'{name}: {"KILLED" if killed else "INVALID_OR_SURVIVED"} {first}', flush=True)
(args.evidence_dir / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
if not all(item['killed'] for item in results):
    raise SystemExit(1)
