"""Linux test-runner ownership and bounded descendant cleanup, stdlib only."""
import ctypes
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def process_info(pid):
    try:
        fields = Path('/proc', str(pid), 'stat').read_text().rsplit(') ', 1)[1].split()
        return {'pid': int(pid), 'state': fields[0], 'parent': int(fields[1]),
                'group': int(fields[2]), 'session': int(fields[3]), 'start': fields[19]}
    except (OSError, ValueError, IndexError):
        return None


def all_processes():
    return [info for path in Path('/proc').iterdir() if path.name.isdigit()
            and (info := process_info(path.name)) is not None]


def enable_subreaper():
    # Orphans from an interrupted Flutter worker are adopted by this runner,
    # which can wait/reap them instead of leaving zombies with container PID1.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        raise RuntimeError('owned_process_subreaper_unavailable')


def recorded_processes(evidence):
    result = {}
    for path in Path(evidence).glob('*/launch-*/launch.json'):
        try:
            record = json.loads(path.read_text())
            for key in ('pid', 'launcher_pid'):
                pid = record[key]
                info = process_info(pid)
                if info is not None and info['start'] == record.get(key + '_start'):
                    result[pid] = info
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return result


def run_owned(command, *, cwd, environment, evidence, timeout=240, grace=0.5):
    enable_subreaper()
    preexisting = {info['pid'] for info in all_processes() if info['parent'] == os.getpid()}
    child = subprocess.Popen(command, cwd=cwd, env=environment, start_new_session=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    session = child.pid
    first = process_info(child.pid)
    observed = {child.pid: first} if first is not None else {}
    forced = []
    reaped = []
    timed_out = False
    output = b''

    def members():
        recorded = recorded_processes(evidence)
        current = {}
        for info in all_processes():
            owned = (info['session'] == session or
                     (info['parent'] == os.getpid() and info['pid'] not in preexisting))
            known = observed.get(info['pid'])
            if known is not None and info['start'] == known['start']:
                owned = True
            if info['pid'] in recorded:
                owned = True
            if owned:
                current[info['pid']] = info
                observed.setdefault(info['pid'], info)
        return current

    def reap():
        child.poll()  # Popen keeps ownership of its direct child's status.
        for pid, info in members().items():
            if pid != child.pid and info['parent'] == os.getpid():
                try:
                    done, _ = os.waitpid(pid, os.WNOHANG)
                    if done:
                        reaped.append(done)
                except ChildProcessError:
                    pass

    def wait_empty(seconds):
        deadline = time.monotonic() + seconds
        while True:
            reap()
            if not members():
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.01)

    def terminate(sig):
        owned = members()
        group = [info for info in owned.values() if info['group'] == session and info['state'] != 'Z']
        if group:
            try:
                os.killpg(session, sig)
                forced.append({'group': session, 'signal': sig})
            except ProcessLookupError:
                pass
        for pid, info in owned.items():
            if info['group'] == session or info['state'] == 'Z':
                continue
            now = process_info(pid)
            if now is not None and now['start'] == info['start']:
                try:
                    os.kill(pid, sig)
                    forced.append({'pid': pid, 'start': info['start'], 'signal': sig})
                except ProcessLookupError:
                    pass

    previous = signal.getsignal(signal.SIGTERM)
    def interrupted(signum, frame):
        raise InterruptedError('owned_runner_interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    try:
        try:
            output, _ = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            timed_out = True
            output = error.output or b''
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        # A successful root exit does not prove its workers/children are gone.
        natural = wait_empty(grace if not timed_out else 0)
        if not natural:
            terminate(signal.SIGTERM)
            if not wait_empty(2):
                terminate(signal.SIGKILL)
                wait_empty(3)
        try:
            output, _ = child.communicate(timeout=2)
        except subprocess.TimeoutExpired as error:
            terminate(signal.SIGKILL)
            wait_empty(2)
            output = (error.output or output) + b'\nowned_process_pipes_did_not_close'
        finally:
            signal.signal(signal.SIGTERM, previous)
        reap()
        remaining = members()
        cleanup = {'natural': natural, 'forced': forced, 'safe': not remaining,
                   'session': session, 'owned_pids': sorted(observed),
                   'reaped_adopted_pids': sorted(set(reaped)), 'remaining': list(remaining.values())}
        Path(evidence).parent.mkdir(parents=True, exist_ok=True)
        Path(str(evidence) + '-watchdog.json').write_text(json.dumps(cleanup, indent=2) + '\n')
    return {'returncode': child.returncode, 'stdout': output.decode(errors='replace'),
            'timed_out': timed_out, 'cleanup': cleanup}
