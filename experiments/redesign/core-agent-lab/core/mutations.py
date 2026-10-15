#!/usr/bin/env python3
"""Run compiled semantic inverse mutants in private copies using existing offline Cargo only."""
import argparse
import json
import re
import sys
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
    ('wire_stale_reported_usage', 'src/agent.rs',
     'if self.state.wire.is_some(){self.state.wire_counters.usage=crate::wire_sse::Usage::default();}',
     ''),
    ('wire_private_history_bound', 'src/wire_provider.rs',
     'wire_json::parse_bounded(raw.as_bytes(),1_048_576)?',
     'wire_json::parse_bounded(raw.as_bytes(),262144)?'),
    ('wire_container_depth', 'src/wire_json.rs',
     "&&depth>=32{return Err(\"wire_json_depth\".into());}",
     "&&depth>32{return Err(\"wire_json_depth\".into());}"),
    ('wire_native_value_identity', 'src/wire_provider.rs',
     'if pending!=Some((call_ref.as_str(),value.as_str()))||!identifier(receipt)',
     'if pending.map(|p|p.0)!=Some(call_ref.as_str())||!identifier(receipt)'),
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
# A separate inverse proves the independent preterminal physical oracle is sensitive.
# Only Decoder.feed's real ArgumentObservation becomes an early Tool. The original
# Agent still owns authorization, confirmation, dispatch and the physical receipt.
# In this mutant only, ACK is relocated after the real effect checkpoint. No finish
# or DONE has been consumed; this is deliberately NOT the baseline hook ordering.
name = 'wire_preterminal_physical_effect'
work = Path(tempfile.mkdtemp(prefix='core-agent-mutation-'))
crate = work / 'core'
shutil.copytree(source, crate, ignore=shutil.ignore_patterns('target', '__pycache__'))
edits = [
    ('src/wire_provider.rs',
     'if decoder.feed(*byte)?.is_some(){control.checkpoint("wire-args")?;control.poll()?;}',
     'if let Some(call)=decoder.feed(*byte)?{let _=child.kill();let _=child.wait();return Ok(ModelEvent::Tool{call_ref:call.call_ref,name:call.name,value:call.value});}'),
    ('src/agent.rs',
     'h.checkpoint("effect")?;self.cancelled()?;',
     'h.checkpoint("wire-args")?;h.checkpoint("effect")?;self.cancelled()?;'),
]
for file, before, after in edits:
    path = crate / file
    text = path.read_text()
    if text.count(before) != 1:
        raise SystemExit(f'{name}: exact mutation site missing in {file}')
    path.write_text(text.replace(before, after, 1))
build = subprocess.run(['cargo', 'build', '--offline', '--locked', '--manifest-path', str(crate / 'Cargo.toml'), '--target-dir', str(crate / 'target')], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
build_log = args.evidence_dir / f'{name}-build.log'
build_log.write_text(build.stdout)
compiled = build.returncode == 0 and ('Finished `dev`' in build.stdout or 'Finished dev' in build.stdout)
checker = source.parent / 'checks' / 'wire_process.py'
check_log = args.evidence_dir / f'{name}.log'
check_text = ''
returncode = -1
if compiled and checker.is_file():
    command = [sys.executable, '-B', str(checker), '--binary', str(crate / 'target/debug/muyon-core-agent-lab'), '--evidence-dir', str(args.evidence_dir / name), '--test-name', 'test_rust_consumed_complete_arguments_ack_before_terminal_has_no_effect']
    try:
        run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        check_text, returncode = run.stdout, run.returncode
    except subprocess.TimeoutExpired as exc:
        check_text = (exc.stdout or b'').decode(errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or '')
        check_text += '\nMUTANT_SETUP_TIMEOUT\n'
else:
    check_text = 'MUTANT_SETUP_INVALID: compilation or independent checker unavailable\n'
check_log.write_text(check_text)
# Retain the full fixture-only log as an artifact, and expose the actual oracle
# evidence in standard CI logs when artifact delivery is unavailable.
print(f'{name}: independent checker excerpt BEGIN', flush=True)
for line in check_text.splitlines():
    if ('RUST_WIRE_ARGS_ACK_OBSERVED' in line or line.startswith('FAIL: ')
            or line.startswith('AssertionError: ') or line.startswith('FAILED (')
            or line.startswith('MUTANT_SETUP_')):
        print(line, flush=True)
print(f'{name}: independent checker excerpt END full_log={check_log}', flush=True)
acknowledged = 'RUST_WIRE_ARGS_ACK_OBSERVED' in check_text
physical_failure = re.search(r'AssertionError: 1 != 0[^\n]*PRETERMINAL_(?:PHYSICAL_EFFECT|CONFIRMATION_CONSUMED)', check_text) is not None
killed = compiled and returncode != 0 and acknowledged and physical_failure and 'MUTANT_SETUP_TIMEOUT' not in check_text and 'FAILED (failures=1)' in check_text
results.append(dict(name=name, killed=killed, returncode=returncode, compiled=compiled, acknowledged=acknowledged, physical_failure=physical_failure, log=str(check_log), build_log=str(build_log), crate=str(crate)))
print(f'{name}: {"KILLED" if killed else "INVALID_OR_SURVIVED"} ACK={acknowledged} physical_assertion={physical_failure}', flush=True)
(args.evidence_dir / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
if not all(item['killed'] for item in results):
    raise SystemExit(1)
