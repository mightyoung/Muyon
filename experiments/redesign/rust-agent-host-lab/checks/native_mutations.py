"""Three native guard inverses; real compile + exact oracle, Linux owned cleanup."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
LAB = Path('experiments/redesign/rust-agent-host-lab')
HOST = LAB / 'core'
PLUGIN = Path('experiments/redesign/plugin-contract-lab/core')
LIB = HOST / 'src/lib.rs'
TARGET = 'native_inverse'
FILTERED = 25  # Fixed original host25 plus one independent final-send oracle.
MUTANTS = [
    dict(name='native_prehandler_fresh_authority',
         before='if fresh != original {', after='if false && fresh != original {',
         test='revoke_after_preinvoke_snapshot_executes_zero', left=1, right=0,
         marker='revocation after the returned pre-invoke snapshot must prevent physical read'),
    dict(name='native_selected_record_scope',
         before='return Err("selected_record_not_authorized".into());', after='return Ok(());',
         test='missing_selected_refs_execute_zero_before_physical_read', left=1, right=0,
         marker='empty current refs must deny before physical handler reads'),
    dict(name='native_final_model_admission',
         before='if self.authority.snapshot()? != current {',
         after='if false && self.authority.snapshot()? != current {',
         test='final_native_send_admission_rechecks_after_policy', left=2, right=1,
         marker='NATIVE_FINAL_SEND_BOUNDARY: post-policy revoke must deny second endpoint bytes',
         reach='NATIVE_FINAL_SEND_REACHED reviews=3 reads=1 receipts=1'),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def members(group):
    found = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
            if int(fields[2]) == group:
                found[int(entry.name)] = fields[19]
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def reap():
    while True:
        try:
            child, _ = os.waitpid(-1, os.WNOHANG)
            if child == 0:
                return
        except ChildProcessError:
            return


def still_owned(known):
    alive = {}
    for pid, start in known.items():
        try:
            fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
            if fields[19] == start:
                alive[pid] = start
        except FileNotFoundError:
            pass
    return alive


def run(command, cwd, env, log, timeout=120):
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    known = {}
    timed_out = False
    forced = False
    output = b''
    try:
        while True:
            known.update(members(process.pid))
            try:
                output, _ = process.communicate(timeout=0.05)
                break
            except subprocess.TimeoutExpired:
                if time.monotonic() - started >= timeout:
                    timed_out = True
                    break
    finally:
        # A test panic may leave owned descendants even after cargo exits. Reap
        # adopted children naturally first, then bound forced cleanup separately.
        until = time.monotonic() + (0 if timed_out else 1)
        while True:
            known.update(members(process.pid))
            if process.poll() is not None:
                reap()
            if not members(process.pid) and not still_owned(known):
                break
            if time.monotonic() >= until:
                forced = True
                for sig in (signal.SIGTERM, signal.SIGKILL):
                    try:
                        os.killpg(process.pid, sig)
                    except ProcessLookupError:
                        pass
                    for pid in still_owned(known):
                        try:
                            os.kill(pid, sig)
                        except ProcessLookupError:
                            pass
                    time.sleep(0.1)
                break
            time.sleep(0.02)
        try:
            output, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            timed_out = True
        until = time.monotonic() + 2
        while time.monotonic() < until:
            reap()
            if not members(process.pid) and not still_owned(known):
                break
            time.sleep(0.02)
        clean = not members(process.pid) and not still_owned(known)
        log.write_bytes(output)
    return dict(command=command, returncode=process.returncode, timeout=timed_out,
                cleanup=dict(all_reaped=clean, forced=forced, natural=clean and not forced,
                             known_pids=known, remaining_pids=still_owned(known)),
                raw_sha256=sha(log), log=str(log))


def oracle(text, result, contract, mutant):
    expected_status = 'FAILED' if mutant else 'ok'
    rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', text, re.M)
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', text, re.M)
    valid = (result['returncode'] == (101 if mutant else 0) and not result['timeout']
             and result['cleanup']['all_reaped'] and (mutant or result['cleanup']['natural'])
             and bool(re.search(r'Finished [^\n]*test[^\n]*profile', text))
             and not re.search(r'SIGABRT|SIGKILL|signal:|timed out|Timeout|could not compile|MUTANT_SETUP', text)
             and len(re.findall(r'Running tests/native_inverse\.rs \(', text)) == 1
             and rows == [(contract['test'], expected_status)]
             and summaries == [(expected_status, '0' if mutant else '1', '1' if mutant else '0', '0', '0', str(FILTERED))])
    if mutant:
        panics = re.findall(r"thread '([^']+)'(?: \(\d+\))? panicked at [^\n]+:\n([^\n]+)\n\s*left: (\d+)\n\s*right: (\d+)", text)
        valid = (valid and len(panics) == 1 and panics[0][0] == contract['test']
                 and panics[0][1].endswith(contract['marker'])
                 and panics[0][2:] == (str(contract['left']), str(contract['right'])))
    if contract.get('reach'):
        valid = valid and text.count(contract['reach']) == 1
        if mutant:
            valid = valid and text.index(contract['reach']) < text.index("thread '")
    return bool(valid)


def copy_source(root, destination):
    for name in ['core-agent-lab', 'plugin-contract-lab', 'rust-agent-host-lab']:
        path = Path('experiments/redesign') / name
        shutil.copytree(root / path, destination / path,
                        ignore=shutil.ignore_patterns('target', '__pycache__'))
    shutil.copyfile(HERE / 'native_inverse.rs', destination / HOST / 'tests/native_inverse.rs')


def compile_copy(root, work, evidence):
    env = os.environ.copy()
    env['CARGO_TARGET_DIR'] = str(work / 'target')
    binary = work / 'target/debug/muyon-plugin-contract-lab'
    env['MUYON_PLUGIN_CONTRACT_BIN'] = str(binary)
    records = []
    for name, command in [
        ('build', ['cargo', 'build', '--offline', '--locked', '--manifest-path', str(PLUGIN / 'Cargo.toml'), '--bin', 'muyon-plugin-contract-lab']),
        ('compile', ['cargo', 'test', '--offline', '--locked', '--no-run', '--manifest-path', str(HOST / 'Cargo.toml'), '--test', TARGET]),
    ]:
        result = run(command, work, env, evidence / (name + '.log'))
        records.append(result)
        if result['returncode'] != 0 or result['timeout'] or not result['cleanup']['natural']:
            diagnostic(evidence / (name + '.log'))
            return env, records, False
    records[-1]['plugin_binary_sha256'] = sha(binary)
    records[-1]['executables_sha256'] = executables(work)
    return env, records, True


def executables(work):
    return {str(path.relative_to(work)): sha(path) for path in (work / 'target').rglob('*')
            if path.is_file() and os.access(path, os.X_OK)}


def diagnostic(log):
    text = log.read_text(errors='replace')
    print('RAW_DIAGNOSTIC ' + str(log) + '\n' + '\n'.join(text.splitlines()[-45:])[-8000:], flush=True)


def test_copy(work, env, evidence, contract, mutant):
    before = executables(work)
    command = ['cargo', 'test', '--offline', '--locked', '--no-fail-fast', '--manifest-path', str(HOST / 'Cargo.toml'), '--test', TARGET, contract['test'], '--', '--exact', '--nocapture']
    log = evidence / (contract['name'] + '.log')
    result = run(command, work, env, log, timeout=30)
    result['executables_before_sha256'] = before
    result['executables_after_sha256'] = executables(work)
    result['executables_unchanged'] = bool(before) and before == result['executables_after_sha256']
    result['accepted'] = result['executables_unchanged'] and oracle(log.read_text(errors='replace'), result, contract, mutant)
    diagnostic(log)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--evidence-dir', type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    evidence = args.evidence_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    # Adopt and reap orphaned owned descendants, in this dedicated single runner.
    if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
        raise SystemExit('INVALID: Linux child subreaper unavailable')
    expected = json.loads((HERE / 'cases.json').read_text())['components']['host']
    for path, provenance in expected['sources'].items():
        if sha(root / path) != provenance['sha256']:
            raise SystemExit('INVALID: fixed host test source mismatch')
    original = sha(root / LIB)
    tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z',
              'experiments/redesign/core-agent-lab', 'experiments/redesign/plugin-contract-lab',
              str(LAB)], text=True).split('\0')
    source_before = {name: sha(root / name) for name in tracked if name}
    summary = dict(source_sha=subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
                   fixture_sha256=sha(HERE / 'native_inverse.rs'), host_before_sha256=original,
                   source_before_sha256=source_before,
                   contracts=MUTANTS, baselines=[], mutants=[])
    work_root = Path(tempfile.mkdtemp(prefix='rust-native-inverse-'))
    try:
        baseline = work_root / 'baseline'
        copy_source(root, baseline)
        env, compiled, valid = compile_copy(root, baseline, evidence)
        summary['baseline_compile'] = compiled
        if not valid:
            raise RuntimeError('baseline compilation/setup INVALID')
        for contract in MUTANTS:
            result = test_copy(baseline, env, evidence, contract, False)
            summary['baselines'].append(result)
            if not result['accepted']:
                raise RuntimeError('baseline_not_green:' + contract['name'])
        for contract in MUTANTS:
            directory = evidence / contract['name']; directory.mkdir()
            work = work_root / contract['name']; copy_source(root, work)
            path = work / LIB; text = path.read_text()
            if text.count(contract['before']) != 1:
                summary['mutants'].append(dict(name=contract['name'], classification='INVALID', reason='anchor_not_unique'))
                continue
            path.write_text(text.replace(contract['before'], contract['after'], 1))
            shutil.copyfile(path, directory / 'mutated-lib.rs')
            env, compiled, valid = compile_copy(root, work, directory)
            result = test_copy(work, env, directory, contract, True) if valid else dict(accepted=False)
            result.update(name=contract['name'], compile=compiled, classification='KILLED' if result['accepted'] else 'INVALID_OR_SURVIVED')
            summary['mutants'].append(result)
            print(contract['name'] + ': ' + result['classification'], flush=True)
    except (RuntimeError, OSError) as error:
        summary['error'] = str(error)
        print('INVALID: ' + str(error), flush=True)
    finally:
        summary['host_after_sha256'] = sha(root / LIB)
        summary['source_after_sha256'] = {name: sha(root / name) for name in source_before}
        summary['source_unchanged'] = summary['source_after_sha256'] == source_before
        summary['accepted'] = (summary['source_unchanged'] and len(summary['baselines']) == 3
                               and all(row['accepted'] for row in summary['baselines'])
                               and len(summary['mutants']) == 3
                               and all(row['classification'] == 'KILLED' for row in summary['mutants']))
        (evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        # Only rebuildable private targets are removed. Sources/raw evidence stay.
        for target in work_root.glob('*/target'):
            shutil.rmtree(target)
    return 0 if summary['accepted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
