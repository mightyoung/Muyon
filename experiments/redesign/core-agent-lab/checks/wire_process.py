"""Independent actual-request/physical-receipt oracle; no alternate Agent DUT."""
import json


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate captured request key')
        result[key] = value
    return result


def read_request(path):
    return json.loads(path.read_bytes().decode('utf-8'), object_pairs_hook=unique_object)


def assert_native_pair(first, second, value, receipt, call_id='call_native_1', physical_pairs=None):
    expected_schema = {'type': 'object', 'properties': {'value': {'type': 'string'}},
                       'required': ['value'], 'additionalProperties': False}
    for request in [first, second]:
        assert request['model'] == 'fixture-model'
        assert request['stream'] is True
        assert len(request['tools']) == 1
        spec = request['tools'][0]
        assert spec['type'] == 'function'
        assert spec['function']['name'] == 'fixture__record'
        assert spec['function']['parameters'] == expected_schema
    # Expected identities come from independent physical rows, never from request history.
    expected = dict(physical_pairs or {call_id: (value, receipt)})
    assert expected.get(call_id) == (value, receipt)
    last_pair = None
    observed = {}
    for request in [first, second]:
        messages = request['messages']
        index = 0
        while index < len(messages):
            message = messages[index]
            assert message.get('role') != 'tool', 'orphan role=tool result'
            calls = message.get('tool_calls')
            if calls is None:
                index += 1
                continue
            assert message.get('role') == 'assistant', 'native call has wrong role'
            assert isinstance(calls, list) and len(calls) == 1, 'actual assistant.tool_calls missing'
            call = calls[0]
            native_id = call['id']
            assert call['type'] == 'function'
            assert call['function']['name'] == 'fixture__record'
            assert native_id in expected, 'native history has no matching physical receipt'
            expected_value, expected_receipt = expected[native_id]
            arguments = json.loads(call['function']['arguments'], object_pairs_hook=unique_object)
            assert arguments == {'value': expected_value}, 'captured arguments differ from physical effect'
            assert index + 1 < len(messages), 'orphan assistant tool call'
            tool = messages[index + 1]
            assert tool.get('role') == 'tool', 'tool result has no preceding assistant call'
            assert tool.get('tool_call_id') == native_id, 'tool result call ID differs'
            content = json.loads(tool['content'], object_pairs_hook=unique_object)
            assert content.get('value') == expected_value and content.get('receipt') == expected_receipt, 'captured tool content differs from original physical receipt'
            identity = (expected_value, expected_receipt)
            assert observed.setdefault(native_id, identity) == identity, 'repeated native ID changes original binding'
            if request is second:
                last_pair = (native_id, expected_value, expected_receipt)
            index += 2
    assert last_pair == (call_id, value, receipt), 'actual request has no expected final native pair'


# The process layer invokes only the actual Rust executable. Existing C1 readers
# observe physical state; no scripted provider/reply substitute is used here.
import argparse
import hashlib
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time
import unittest

import process as c1_readers

LAB = Path(__file__).resolve().parent.parent
SCENARIOS = LAB / 'fixtures/wire/scenarios'
HELPER = LAB / 'fixtures/wire/fake_service.py'
BINARY = None
EVIDENCE = None
WIRE_KEYS = ['wire_sent_bytes', 'wire_received_bytes', 'wire_total_bytes']


def wait_rust_ack(child, boundary, timeout=20):
    selector = selectors.DefaultSelector()
    try:
        selector.register(child.stdout, selectors.EVENT_READ)
        assert selector.select(timeout=timeout), 'missing actual Rust checkpoint'
        marker = child.stdout.readline().strip()
        assert marker == 'checkpoint='+boundary, 'wrong/early-exit Rust checkpoint'
    finally:
        selector.close()


class WireProcessTests(unittest.TestCase):
    serial = 0

    def directory(self):
        type(self).serial += 1
        return EVIDENCE / f'{self._testMethodName}-{self.serial}'

    def log(self, args, result):
        with (EVIDENCE/'commands.jsonl').open('a') as stream:
            stream.write(json.dumps({'argv': list(map(str, args)), 'exit': result.returncode,
                                     'stdout': result.stdout, 'stderr': result.stderr})+'\n')

    def command(self, verb, directory, *flags, code=0):
        args = [str(BINARY), verb, '--dir', str(directory), *map(str, flags)]
        result = subprocess.run(args, text=True, capture_output=True, timeout=25)
        self.log(args, result)
        self.assertEqual(result.returncode, code, (args, result.stdout, result.stderr))
        if code:
            self.assertIn('error=', result.stderr)
            return result
        actual = c1_readers.observation(result.stdout)
        self.assertIn('status', actual)
        return actual

    def start(self, directory, scenario='happy', **facts):
        args = ['--provider', 'chat-sse', '--wire-helper', str(HELPER.resolve()),
                '--wire-fixtures', str((SCENARIOS/scenario).resolve()),
                '--input', 'synthetic wire input', '--mode', 'full-allow']
        # Replace defaults instead of sending duplicate host flags.
        if 'input' in facts:
            args[args.index('--input')+1] = facts.pop('input')
        if 'mode' in facts:
            args[args.index('--mode')+1] = facts.pop('mode')
        for key, value in facts.items():
            if isinstance(value, bool):
                value = str(value).lower()
            args += ['--'+key.replace('_','-'), str(value)]
        self.addCleanup(self.cleanup_children, directory)
        return self.command('start', directory, *args)

    def captures(self, directory):
        return sorted((directory/'wire-capture').glob('request-*.json'))

    def capture_snapshot(self, directory):
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted((directory/'wire-capture').glob('*')) if p.is_file()}

    def wait_fixture_capture(self, directory, turn=1):
        # Only service/PID readiness, never proof Rust consumed argument bytes.
        # Release depends on observed files, not an elapsed sleep interval.
        paths = [directory/f'wire-capture/request-{turn}.json', directory/f'wire-capture/child-{turn}.pid']
        deadline = time.monotonic()+5
        while not all(path.exists() for path in paths):
            remaining = deadline-time.monotonic()
            self.assertGreater(remaining,0,'fake service did not capture admitted request')
            time.sleep(min(0.005,remaining))

    def cleanup_children(self, directory):
        # SIGKILL cannot run Rust Drop. This is harness cleanup of trusted fake
        # children, not a parent-death guarantee. Normal path asserts gone first.
        for path in (directory/'wire-capture').glob('child-*.pid'):
            pid = int(path.read_text())
            record = {'pid': pid, 'directory': str(directory), 'action': 'already_gone'}
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                os.kill(pid, signal.SIGKILL)
                record['action'] = 'harness_sigkill_after_parent_exit'
                try:
                    os.waitpid(pid, 0)
                    record['reap'] = 'harness_waitpid'
                except ChildProcessError:
                    # The child is adopted by the OS reaper after Rust dies.
                    # Poll actual disappearance; this is cleanup, never stream order.
                    deadline = time.monotonic()+2
                    while Path(f'/proc/{pid}').exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    record['reap'] = 'os_reaper' if not Path(f'/proc/{pid}').exists() else 'not_harness_child_dead_pending_os_reap'
            with (EVIDENCE/'helper-cleanup.jsonl').open('a') as stream:
                stream.write(json.dumps(record)+'\n')

    def assert_children_reaped(self, directory):
        for path in (directory/'wire-capture').glob('child-*.pid'):
            pid = int(path.read_text())
            with self.assertRaises(ProcessLookupError, msg=f'handled exit did not reap helper PID{pid}'):
                os.kill(pid, 0)

    def pause(self, directory, boundary):
        args = [str(BINARY), 'run', '--dir', str(directory), '--checkpoint', boundary]
        child = subprocess.Popen(args, text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, bufsize=1)
        self.addCleanup(self.reap_rust, child)
        wait_rust_ack(child, boundary)
        return child

    @staticmethod
    def reap_rust(child):
        if child.poll() is None:
            child.kill()
        child.communicate(timeout=10)

    def release(self, child):
        child.stdin.write('\n'); child.stdin.flush()
        stdout, stderr = child.communicate(timeout=25)
        self.assertEqual(child.returncode, 0, stderr)
        return c1_readers.observation(stdout)

    def assert_wire_counters(self, actual):
        for key in WIRE_KEYS:
            self.assertGreaterEqual(int(actual[key]), 0)
        self.assertEqual(int(actual['wire_total_bytes']), int(actual['wire_sent_bytes'])+int(actual['wire_received_bytes']))

    def assert_complete_capture_bytes(self, directory, actual):
        captures = directory/'wire-capture'
        sent = sum(p.stat().st_size for p in captures.glob('request-*.json'))
        received = sum(p.stat().st_size for p in captures.glob('emitted-*.sse'))
        self.assertEqual(int(actual['wire_sent_bytes']), sent)
        self.assertEqual(int(actual['wire_received_bytes']), received)
        self.assert_wire_counters(actual)

    def assert_effects(self, directory, count):
        physical = c1_readers.physical(directory)
        self.assertEqual(physical['count'], count)
        return physical

    def assert_happy(self, directory, actual, value='wire-value', call_id='call_native_1', turns=2):
        self.assertEqual(actual['status'], 'completed')
        physical = self.assert_effects(directory, 1)
        receipt = physical['rows'][0][7]
        self.assertEqual(bytes.fromhex(physical['value']).decode(), value)
        self.assertEqual(actual['receipt'], receipt)
        self.assertEqual(int(actual['model_calls']), turns)
        self.assertEqual(len(self.captures(directory)), turns)
        first = read_request(directory/'wire-capture/request-1.json')
        for turn in range(2, turns + 1):
            following = read_request(directory/f'wire-capture/request-{turn}.json')
            assert_native_pair(first, following, value, receipt, call_id)
        self.assertEqual(json.loads(bytes.fromhex(actual['answer_hex']).decode()), {'value':value,'receipt':receipt})
        for path in self.captures(directory):
            self.assertNotIn(str(directory).encode(), path.read_bytes())
            self.assertNotIn(str(HELPER.resolve()).encode(), path.read_bytes())
        self.assert_complete_capture_bytes(directory, actual)
        self.assert_children_reaped(directory)
        return physical

    def test_independent_raw_sse_valid_and_invalid_matrix(self):
        cases = json.loads((SCENARIOS/'cases.json').read_text())['cases']
        for case in cases:
            with self.subTest(scenario=case['scenario']):
                directory = self.directory()
                self.start(directory, case['scenario'])
                actual = self.command('run', directory)
                if case['accept']:
                    self.assert_happy(directory, actual, case['value'])
                else:
                    self.assertNotEqual(actual['status'], 'completed')
                    self.assertEqual(actual['answer_hex'], '')
                    self.assertEqual(actual['confirmations'], '0')
                    self.assert_effects(directory, 0)
                    self.assertLessEqual(len(self.captures(directory)), 1)
                    self.assertNotIn('SYNTHETIC_PROVIDER_DETAIL', actual['reason'])
                    self.assertNotIn('SYNTHETIC_HELPER_DETAIL', actual['reason'])
                    self.assert_wire_counters(actual)
                    before = self.capture_snapshot(directory)
                    self.command('run', directory)
                    self.assertEqual(self.capture_snapshot(directory), before, 'implicit stream retry/fallback')
                    self.assert_children_reaped(directory)

    def test_same_raw_bytes_with_whole_byte_and_seven_byte_reads(self):
        for scenario,value in [('happy','wire-value'),('unicode','线😀'),('escaped-pair','😀'),('crlf-comments','wire-value')]:
            normalized = []
            for size in [8192,1,7]:
                with self.subTest(scenario=scenario, read_bound=size):
                    directory = self.directory()
                    self.start(directory, scenario, wire_chunk_size=size)
                    actual = self.command('run', directory)
                    self.assert_happy(directory, actual, value)
                    normalized.append((actual['status'], bytes.fromhex(actual['value_hex']).decode(),
                                       actual['model_calls'], actual['confirmations']))
            self.assertEqual(normalized, [normalized[0]]*3)

    def test_rust_consumed_complete_arguments_ack_before_terminal_has_no_effect(self):
        directory = self.directory()
        self.start(directory, 'preterminal', mode='ask-every-time', confirmed=True)
        running = self.pause(directory, 'wire-args')
        persisted = c1_readers.journal(directory)
        print('RUST_WIRE_ARGS_ACK_OBSERVED', flush=True)
        self.assertEqual(c1_readers.physical(directory)['count'], 0, 'PRETERMINAL_PHYSICAL_EFFECT')
        self.assertEqual(persisted['calls'], '1')
        self.assertEqual(persisted['steps'], '1')
        self.assertEqual(persisted['confirmations'], '0', 'PRETERMINAL_CONFIRMATION_CONSUMED')
        self.assertGreater(int(persisted['wire_sent_bytes']),0)
        self.assertGreater(int(persisted['wire_received_bytes']),0)
        self.assertIn(persisted['provider_inflight'], {'1','true'})
        completed = self.release(running)
        self.assert_happy(directory, completed)
        self.assertEqual(completed['confirmations'], '1')

    def test_ack_preterminal_cancellation_not_partial_argument_process_claim(self):
        directory = self.directory()
        self.start(directory, 'preterminal', mode='ask-every-time', confirmed=True)
        running = self.pause(directory, 'wire-args')
        persisted = c1_readers.journal(directory)
        self.assertEqual(persisted['confirmations'], '0')
        self.assert_effects(directory, 0)
        self.command('cancel', directory)
        stopped = self.release(running)
        self.assertEqual(stopped['answer_hex'], '')
        self.assertNotEqual(stopped['status'], 'completed')
        self.assertEqual(stopped['confirmations'], '0')
        self.assertEqual(stopped['model_calls'], '1')
        self.assert_effects(directory, 0)
        self.assertEqual(len(self.captures(directory)),1)
        self.assert_children_reaped(directory)

    def test_final_args_are_revalidated_after_early_completeness_ack(self):
        directory = self.directory()
        self.start(directory, 'args-then-trailing-fragment')
        running = self.pause(directory, 'wire-args')
        self.assert_effects(directory,0)
        stopped = self.release(running)
        self.assertNotEqual(stopped['status'],'completed')
        self.assertEqual(stopped['answer_hex'],'')
        self.assert_effects(directory,0)
        self.assert_children_reaped(directory)

    def test_wire_policy_modes_and_hard_gate_facts_remain_host_owned(self):
        for mode,risk,confirmed,effects in [('read-only','low',True,0),('ask-every-time','low',False,0),
                ('ask-every-time','low',True,1),('auto','low',False,1),('auto','high',False,0),
                ('auto','high',True,1),('full-allow','high',False,1)]:
            with self.subTest(mode=mode,risk=risk,confirmed=confirmed):
                directory=self.directory();self.start(directory,mode=mode,risk=risk,confirmed=confirmed)
                actual=self.command('run',directory);self.assert_effects(directory,effects)
                if effects:self.assert_happy(directory,actual)
                else:self.assertNotEqual(actual['status'],'completed');self.assertEqual(actual['answer_hex'],'')
                if mode=='full-allow':self.assertEqual(actual['confirmations'],'0')
        for flag,value in [('hard_ok',False),('scope_ok',False),('revoked',True),('classification_ok',False)]:
            with self.subTest(hard_gate=flag):
                directory=self.directory();self.start(directory,mode='full-allow',risk='high',confirmed=True,**{flag:value})
                actual=self.command('run',directory);self.assert_effects(directory,0)
                self.assertNotEqual(actual['status'],'completed');self.assertEqual(actual['answer_hex'],'')

    def test_dsml_and_tool_like_content_is_plain_text_not_tool_authority(self):
        directory=self.directory();self.start(directory,'text-only')
        actual=self.command('run',directory)
        self.assertEqual(actual['status'],'completed')
        self.assertIn('DSML',bytes.fromhex(actual['answer_hex']).decode())
        self.assert_effects(directory,0);self.assertEqual(len(self.captures(directory)),1)
        self.assert_children_reaped(directory)

    def test_usage_only_chunk_is_optional_and_missing_is_unknown(self):
        directory=self.directory();self.start(directory,'usage-only',mode='ask-every-time')
        waiting=self.command('run',directory)
        self.assertEqual(waiting['status'],'waiting')
        self.assertEqual(waiting['usage_prompt'],'5');self.assertEqual(waiting['usage_completion'],'6')
        other=self.directory();self.start(other,mode='ask-every-time')
        missing=self.command('run',other)
        self.assertEqual(missing['usage_prompt'],'unknown');self.assertEqual(missing['usage_completion'],'unknown')
        self.assert_effects(directory,0);self.assert_effects(other,0)

    def test_silent_service_cancel_and_idle_deadline_reap_real_child(self):
        directory=self.directory();self.start(directory,'silent')
        running=self.pause(directory,'wire-open')
        self.wait_fixture_capture(directory)
        self.command('cancel',directory);stopped=self.release(running)
        self.assertNotEqual(stopped['status'],'completed');self.assert_effects(directory,0)
        self.assert_children_reaped(directory)
        other=self.directory();self.start(other,'silent',wire_idle_ms=100,wire_total_ms=1000)
        before=time.monotonic();failed=self.command('run',other)
        self.assertLess(time.monotonic()-before,5)
        self.assertNotEqual(failed['status'],'completed');self.assert_effects(other,0)
        self.assert_children_reaped(other)

    def test_total_deadline_includes_child_wait_after_stdout_eof(self):
        directory=self.directory();self.start(directory,'eof-hold',wire_idle_ms=1000,wire_total_ms=300)
        before=time.monotonic();failed=self.command('run',directory)
        self.assertLess(time.monotonic()-before,5)
        self.assertNotEqual(failed['status'],'completed');self.assertEqual(failed['answer_hex'],'')
        self.assert_effects(directory,0);self.assert_children_reaped(directory)

    def test_total_deadline_with_controlled_nonreading_stdin_child(self):
        directory=self.directory();self.start(directory,'no-stdin',input='X'*50000,wire_idle_ms=1000,wire_total_ms=300)
        before=time.monotonic();failed=self.command('run',directory)
        self.assertLess(time.monotonic()-before,5)
        self.assertNotEqual(failed['status'],'completed');self.assert_effects(directory,0)
        self.assert_children_reaped(directory)

    def test_cancel_after_committed_effect_keeps_receipt_and_no_next_request(self):
        directory=self.directory();self.start(directory)
        running=self.pause(directory,'effect')
        original=self.assert_effects(directory,1)
        self.command('cancel',directory);stopped=self.release(running)
        self.assertEqual(stopped['receipt'],original['rows'][0][7])
        self.assertEqual(stopped['answer_hex'],'');self.assertEqual(stopped['model_calls'],'1')
        self.assertEqual(len(self.captures(directory)),1)
        self.assertEqual(c1_readers.physical(directory),original)
        self.assert_children_reaped(directory)

    def test_sigkill_after_consumption_ack_holds_admission_without_resend(self):
        directory=self.directory();self.start(directory)
        running=self.pause(directory,'wire-args')
        durable=c1_readers.journal(directory)
        self.assertGreater(int(durable['wire_total_bytes']),0)
        before=self.capture_snapshot(directory)
        running.kill();running.communicate(timeout=10)
        self.assertEqual(running.returncode,-signal.SIGKILL)
        for verb in ['inspect','run','run']:
            stopped=self.command(verb,directory)
            self.assertNotEqual(stopped['status'],'completed')
            self.assertEqual(stopped['model_calls'],durable['calls'])
            for key in WIRE_KEYS:self.assertGreaterEqual(int(stopped[key]),int(durable[key]))
            self.assertEqual(self.capture_snapshot(directory),before,'crash triggered another helper/request')
            self.assert_effects(directory,0)
        # addCleanup explicitly terminates any survivor; no parent-death claim.

    def test_persistent_model_call_and_wire_budget_do_not_reset_on_reopen(self):
        directory=self.directory();self.start(directory,max_calls=1)
        exhausted=self.command('run',directory)
        self.assertEqual(exhausted['status'],'budget_exhausted');self.assert_effects(directory,1)
        before=self.capture_snapshot(directory)
        for verb in ['inspect','run','lookup','run']:
            again=self.command(verb,directory)
            self.assertEqual(again['status'],'budget_exhausted')
            self.assertEqual(again['model_calls'],exhausted['model_calls'])
            for key in WIRE_KEYS:self.assertEqual(again[key],exhausted[key])
            self.assertEqual(self.capture_snapshot(directory),before)
        other=self.directory();self.start(other,'response-limit',max_wire_total=2000)
        stopped=self.command('run',other)
        self.assertNotEqual(stopped['status'],'completed');self.assert_effects(other,0)
        self.assertGreater(int(stopped['wire_total_bytes']),0)
        before=self.capture_snapshot(other)
        again=self.command('run',other)
        self.assertEqual(self.capture_snapshot(other),before)
        for key in WIRE_KEYS:self.assertEqual(again[key],stopped[key])
        self.assert_children_reaped(other)

    def test_original_native_correlation_replay_and_conflict_remain_physical(self):
        directory=self.directory();self.start(directory,'replay',mode='ask-every-time',confirmed=True)
        completed=self.command('run',directory)
        self.assert_happy(directory,completed,turns=3)
        self.assertEqual(completed['confirmations'],'1')
        other=self.directory();self.start(other,'conflict')
        conflicted=self.command('run',other)
        original=self.assert_effects(other,1)
        self.assertEqual(bytes.fromhex(original['value']).decode(),'wire-value')
        self.assertIn('conflict',conflicted['reason'])
        self.assertEqual(conflicted['answer_hex'],'');self.assertEqual(len(self.captures(other)),2)

    def test_wire_r1_terminal_receipt_restore_cannot_start_new_exchange(self):
        for budget in [False,True]:
            with self.subTest(budget_terminal=budget):
                directory=self.directory();self.start(directory,**({'max_calls':1} if budget else {}))
                terminal=self.command('run',directory)
                expected='budget_exhausted' if budget else 'completed'
                self.assertEqual(terminal['status'],expected)
                original=self.assert_effects(directory,1);before=self.capture_snapshot(directory)
                effect=directory/'effects.db';held=directory/'r1-original-evidence.db'
                original_bytes=effect.read_bytes();effect.rename(held)
                unknown=self.command('run',directory);self.assertEqual(unknown['status'],'outcome_unknown')
                held.rename(effect);looked=self.command('lookup',directory);again=self.command('run',directory)
                self.assertEqual(looked['status'],expected);self.assertEqual(again['status'],expected)
                self.assertEqual(effect.read_bytes(),original_bytes)
                self.assertEqual(c1_readers.physical(directory),original)
                self.assertEqual(self.capture_snapshot(directory),before)
                for key in WIRE_KEYS+['model_calls','confirmations']:self.assertEqual(again[key],terminal[key])

    def test_wire_r2_historical_receipt_hold_preserves_waiting_next_native_call(self):
        directory=self.directory();self.start(directory,'two-wire-effects',mode='ask-every-time',confirmed=True)
        waiting=self.command('run',directory)
        self.assertEqual(waiting['status'],'waiting');self.assertEqual(waiting['model_calls'],'2')
        self.assertEqual(waiting['confirmations'],'1');original=self.assert_effects(directory,1)
        effect=directory/'effects.db';held=directory/'r2-original-evidence.db'
        original_bytes=effect.read_bytes();before=self.capture_snapshot(directory);effect.rename(held)
        unknown=self.command('inspect',directory);self.assertEqual(unknown['status'],'outcome_unknown')
        args=[str(BINARY),'run','--dir',str(directory),'--confirmed','true']
        attempt=subprocess.run(args,text=True,capture_output=True,timeout=20);self.log(args,attempt)
        self.assertIn(attempt.returncode,[0,2])
        if not attempt.returncode:self.assertEqual(c1_readers.observation(attempt.stdout)['confirmations'],'1')
        held.rename(effect);restored=self.command('lookup',directory)
        self.assertEqual(restored['status'],'waiting');self.assertEqual(restored['invocation'],waiting['invocation'])
        self.assertEqual(restored['confirmations'],'1');self.assertEqual(restored['model_calls'],'2')
        self.assertEqual(effect.read_bytes(),original_bytes);self.assertEqual(self.capture_snapshot(directory),before)
        completed=self.command('run',directory,'--confirmed','true')
        self.assertEqual(completed['status'],'completed');self.assertEqual(completed['confirmations'],'2')
        final=self.assert_effects(directory,2);self.assertEqual(final['rows'][0],original['rows'][0])
        self.assertEqual(bytes.fromhex(final['value']).decode(),'wire-second')
        for row, expected_value in zip(final['rows'], ['wire-first', 'wire-second']):
            self.assertEqual(bytes.fromhex(row[6]).decode('utf-8'), expected_value,
                             'physical receipt row value differs from independent fixture input')
        assert_native_pair(read_request(directory/'wire-capture/request-1.json'),
                           read_request(directory/'wire-capture/request-2.json'),
                           'wire-first', final['rows'][0][7])
        assert_native_pair(read_request(directory/'wire-capture/request-1.json'),
                           read_request(directory/'wire-capture/request-3.json'),
                           'wire-second',final['rows'][1][7],'call_native_2',
                           physical_pairs={'call_native_1': ('wire-first', final['rows'][0][7]),
                                           'call_native_2': ('wire-second', final['rows'][1][7])})
        self.assert_children_reaped(directory)

    def test_invalid_or_mutable_wire_configuration_is_not_model_authority(self):
        for flag,value in [('wire-chunk-size','0'),('wire-chunk-size','8193'),('wire-idle-ms','0'),
                           ('wire-total-ms','30001'),('max-wire-total','1048577')]:
            directory=self.directory()
            self.command('start',directory,'--provider','chat-sse','--wire-helper',HELPER,
                         '--wire-fixtures',SCENARIOS/'happy','--'+flag,value,code=2)
            self.assert_effects(directory,0)
        directory=self.directory();self.start(directory)
        self.command('run',directory,'--wire-helper',HELPER,code=2)
        self.assertEqual(len(self.captures(directory)),0)


def main():
    global BINARY,EVIDENCE
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',required=True);parser.add_argument('--evidence-dir',required=True)
    parser.add_argument('--test-name',help='One named independent method, for targeted semantic mutants')
    args=parser.parse_args();BINARY=Path(args.binary).resolve(strict=True);EVIDENCE=Path(args.evidence_dir).resolve()
    if EVIDENCE.is_relative_to(LAB):raise ValueError('raw evidence must stay outside lab')
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    assert os.access(BINARY,os.X_OK),'actual binary is not executable'
    sha=subprocess.check_output(['git','-C',str(LAB),'rev-parse','HEAD'],text=True).strip()
    identity={'source_sha':sha,'binary_sha256':hashlib.sha256(BINARY.read_bytes()).hexdigest(),
              'scope':'actual offline Rust stdio/SSE process; no HTTP/network/model/native acceptance'}
    (EVIDENCE/'identity.json').write_text(json.dumps(identity,indent=2)+'\n')
    if args.test_name:
        if not args.test_name.startswith('test_') or not hasattr(WireProcessTests,args.test_name):
            parser.error('unknown independent test name')
        suite=unittest.TestSuite([WireProcessTests(args.test_name)])
    else:
        suite=unittest.defaultTestLoader.loadTestsFromTestCase(WireProcessTests)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    summary={**identity,'methods':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'success':result.wasSuccessful()}
    (EVIDENCE/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary))
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__=='__main__':main()
