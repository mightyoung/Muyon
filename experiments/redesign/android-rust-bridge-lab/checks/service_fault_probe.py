"""Bounded private-source-copy probes. No production feature, FFI, or provider override."""
import argparse
from collections import Counter
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
DESCRIPTOR = HERE / 'service_fault_cases.json'
CONTRACT = json.loads(DESCRIPTOR.read_text())
CORE = 'experiments/redesign/rust-agent-host-lab/core'
CAPTURE_ANCHOR = '    // Preserve original receipt success even when overall cancellation or storage failure occurs.\n'
CANCEL_ANCHOR = '        self.control.poll()?;\n        control.poll()?;\n        let position = self.frames.borrow().len();\n'
LEDGER_ANCHOR = '    pub fn ledger(&self, status: &str, body: &[u8]) -> Result<()> {\n'
ASSERTION = 'SERVICE_PRIVATE_FAULT_RED: preserve actual receipt and normalized terminal'
CAPTURE = '''    let probe_receipt = service_evidence::receipt(&dir, &run).expect("probe_actual_receipt");
    assert_eq!(probe_receipt.outcome, AgentReceiptOutcome::RecordedSuccess);
    let probe_evidence = std::path::PathBuf::from(std::env::var("SERVICE_FAULT_EVIDENCE").unwrap());
    std::fs::write(probe_evidence.join("original-native.db"), std::fs::read(dir.join("native.db")).unwrap()).unwrap();
    std::fs::write(probe_evidence.join("original-opaque.txt"), probe_receipt.opaque_id.as_ref().unwrap()).unwrap();
    std::fs::write(probe_evidence.join("run-dir.txt"), dir.to_str().unwrap()).unwrap();
    println!("FAULT_RECORDED actual_read=success receipt=RecordedSuccess");
'''


def replace_once(source, anchor, replacement):
    if source.count(anchor) != 1:
        raise RuntimeError('service_fault_anchor_invalid')
    return source.replace(anchor, replacement, 1)


def instrument(sources, case):
    if case not in CONTRACT['cases'] or set(sources) != set(CONTRACT['source_sha256']):
        raise RuntimeError('service_fault_case_invalid')
    for name, digest in CONTRACT['source_sha256'].items():
        if hashlib.sha256(sources[name]).hexdigest() != digest:
            raise RuntimeError('service_fault_source_invalid')
    result = {name: body.decode() for name, body in sources.items()}
    capture = CAPTURE + ('    panic!("SERVICE_PRIVATE_WORKER_PANIC");\n' if case == 'c2_worker_panic' else '')
    result['service_controller.rs'] = replace_once(result['service_controller.rs'], CAPTURE_ANCHOR, capture + CAPTURE_ANCHOR)
    if CONTRACT.get('lease_probe'):
        anchor = '    pub fn await_settled(&self) -> AgentSnapshotReply {\n'
        helper = '    pub fn private_probe_worker_finished(&self) -> bool {\n        self.shared.lock().worker.as_ref().map(|h| h.is_finished()).unwrap_or(false)\n    }\n'
        result['service_controller.rs'] = replace_once(result['service_controller.rs'], anchor, helper + anchor)
    if case != 'c2_worker_panic':
        result['service_runtime.rs'] = replace_once(result['service_runtime.rs'], CANCEL_ANCHOR,
            '        if self.frames.borrow().len() == 1 {\n            println!("FAULT_CANCEL turn=2 before_original_poll=true");\n            self.control.request_cancel();\n        }\n' + CANCEL_ANCHOR)
    if case == 'c3_failed_ledger':
        result['store.rs'] = replace_once(result['store.rs'], LEDGER_ANCHOR, LEDGER_ANCHOR +
            '        if status == "failed" {\n            println!("FAULT_LEDGER error=probe_failed_ledger_io not_diskfull=true");\n            return Err("probe_failed_ledger_io".into());\n        }\n')
    return result


def classify(case, raw, status):
    contract = CONTRACT['cases'][case]
    lease_red = CONTRACT.get('lease_red', False)
    green = contract['observed'] == contract['expected'] and not lease_red
    rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)$', raw, re.M)
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', raw, re.M)
    panic_messages = re.findall(r"^thread '[^']+'(?: \(\d+\))? panicked at [^\n]+:\n([^\n]+)", raw, re.M)
    expected_panics = [] if green else [ASSERTION]
    if case == 'c2_worker_panic':
        expected_panics.append('SERVICE_PRIVATE_WORKER_PANIC')
    observed = f'FAULT_OBSERVED {case} terminal=' + contract['observed']
    markers = ['FAULT_RECORDED actual_read=success receipt=RecordedSuccess', observed]
    if case != 'c2_worker_panic':
        markers.append('FAULT_CANCEL turn=2 before_original_poll=true')
    if case == 'c3_failed_ledger':
        markers.append('FAULT_LEDGER error=probe_failed_ledger_io not_diskfull=true')
    if CONTRACT.get('lease_probe') and case == 'c2_worker_panic':
        markers += ['FAULT_LEASE worker_finished_before_join=busy', 'FAULT_LEASE after_join_before_close=busy', 'FAULT_LEASE after_closed=available']
    if lease_red:
        markers = ['FAULT_RECORDED actual_read=success receipt=RecordedSuccess', 'FAULT_LEASE worker_finished_before_join=available']
        expected_panics = ['SERVICE_PRIVATE_WORKER_PANIC', 'SERVICE_PRIVATE_LEASE_RED: worker completion retains original root until Closed']
    actual_markers = re.findall(r'^FAULT_[^\n]+$', raw, re.M)
    valid = (status == (0 if green else 101)
        and bool(re.search(r'Finished `release` profile', raw))
        and re.findall(r'^\s*Running tests/(\w+)\.rs \(', raw, re.M) == ['service_private_fault']
        and rows == [('service_private_fault_contract', 'ok' if green else 'FAILED')]
        and summaries == [('ok', '1', '0', '0', '0', '0') if green else ('FAILED', '0', '1', '0', '0', '0')]
        and Counter(panic_messages) == Counter(expected_panics)
        and len(re.findall(r'panicked at', raw)) == len(expected_panics)
        and Counter(actual_markers) == Counter(markers)
        and not re.search(r'could not compile|error\[E\d+\]|timed out|signal:|SIGABRT|SIGKILL|No space left|ENOSPC|\ufffd', raw))
    return dict(accepted=valid, classification=('diagnostic_probe_green' if green else 'semantic_red') if valid else 'INVALID',
        case=case, command_exit_code=status, shipping_or_service_green=False,
        expected='worker_finished_before_join=busy' if lease_red else contract['expected'], observed=('worker_finished_before_join=available; receipt_tail_NOT_RUN' if lease_red else contract['observed']) if valid else None)


def prepare(repo, destination, case):
    # git archive fixes *all* compiled dependencies to the author source, not only anchors.
    paths = ['experiments/redesign/' + name for name in ['rust-agent-host-lab', 'core-agent-lab', 'plugin-contract-lab']]
    archive = subprocess.check_output(['git', 'archive', CONTRACT['source_commit'], *paths], cwd=repo)
    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            if member.name.startswith('/') or '..' in Path(member.name).parts or not (member.isfile() or member.isdir()):
                raise RuntimeError('service_fault_archive_invalid')
        tar.extractall(destination, filter='data')
    src = destination / CORE / 'src'
    originals = {name: (src / name).read_bytes() for name in CONTRACT['source_sha256']}
    modified = instrument(originals, case)
    for name, body in modified.items():
        (src / name).write_text(body)
    probe = HERE / ('service_lease_fault_probe.rs' if CONTRACT.get('lease_probe') else 'service_fault_probe.rs')
    (destination / CORE / 'tests/service_private_fault.rs').write_bytes(probe.read_bytes())
    return dict(source_commit=CONTRACT['source_commit'], descriptor_sha256=hashlib.sha256(DESCRIPTOR.read_bytes()).hexdigest(),
        probe_sha256=hashlib.sha256(probe.read_bytes()).hexdigest(), lock_probe_sha256=hashlib.sha256((HERE / 'service_lease_lock_probe.py').read_bytes()).hexdigest(),
        original_sha256=CONTRACT['source_sha256'], private_sha256={name: hashlib.sha256(body.encode()).hexdigest() for name, body in modified.items()})


def main():
    global CONTRACT, DESCRIPTOR
    parser = argparse.ArgumentParser()
    parser.add_argument('--descriptor', type=Path, default=DESCRIPTOR)
    parser.add_argument('--repo', type=Path, default=HERE.parents[3])
    parser.add_argument('--case', choices=CONTRACT['cases'], required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    DESCRIPTOR = args.descriptor.resolve()
    CONTRACT = json.loads(DESCRIPTOR.read_text())
    if (CONTRACT.get('version') != 1 or not re.fullmatch('[a-f0-9]{40}', CONTRACT.get('source_commit', ''))
        or set(CONTRACT.get('source_sha256', {})) != {'service_controller.rs', 'service_runtime.rs', 'model_gateway.rs', 'store.rs'}
        or not all(re.fullmatch('[a-f0-9]{64}', v) for v in CONTRACT['source_sha256'].values())
        or args.case not in CONTRACT.get('cases', {})):
        raise RuntimeError('service_fault_descriptor_invalid')
    evidence = args.evidence_dir.resolve(); evidence.mkdir(parents=True, exist_ok=False)
    work = args.work_dir.resolve()
    provenance = prepare(args.repo, work, args.case)
    (evidence / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    command = ['cargo', '+1.99.0', 'test', '--release', '--locked', '--manifest-path', str(work / CORE / 'Cargo.toml'), '--test', 'service_private_fault', '--', '--show-output', '--test-threads=1']
    (evidence / 'command.json').write_text(json.dumps(command) + '\n')
    if args.prepare_only:
        print('SERVICE_FAULT_PREPARED_NOT_RUN'); return
    env = dict(os.environ, SERVICE_FAULT_CASE=args.case, SERVICE_FAULT_EVIDENCE=str(evidence), SERVICE_FAULT_LOCK_PROBE=str(HERE / 'service_lease_lock_probe.py'))
    with (evidence / 'cargo.log').open('w') as log:
        try:
            status = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=900).returncode
        except subprocess.TimeoutExpired:
            status = 124
    result = classify(args.case, (evidence / 'cargo.log').read_text(errors='replace'), status)
    (evidence / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    # A recognized RED remains a failed command; no aggregate shipping-green claim.
    raise SystemExit(status if result['accepted'] else 1)


if __name__ == '__main__':
    main()
