#!/usr/bin/env python3
"""Independent synthetic OS-process checks for the actual Rust Agent executable.

Fixtures/expected assertions are authored separately; no expected/caseID values
enter provider events. This code observes physical files but implements no Agent,
authorization issuer, effect executor, business wire or receipt generator.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import unittest

LAB = Path(__file__).resolve().parent.parent
BINARY = None
EVIDENCE = None


def observation(text):
    result = {}
    for line in text.splitlines():
        key, separator, value = line.partition('=')
        if not separator or not key or key in result:
            raise AssertionError('invalid/duplicate observation field')
        result[key] = value
    return result


def physical(directory):
    """Independent reader of documented effect snapshot; never supplies receipts."""
    path = directory / 'effects.db'
    if not path.exists():
        return {'present': False, 'count': 0, 'rows': [], 'value': ''}
    lines = path.read_text().splitlines()
    assert lines and lines[0] == 'CORE_EFFECT_V1', 'invalid physical effect header'
    assert len(lines) >= 3, 'truncated physical effect snapshot'
    count = lines[1].split('\t')
    value = lines[2].split('\t')
    assert len(count) == 2 and count[0] == 'count'
    assert len(value) == 2 and value[0] == 'value'
    rows = [line.split('\t') for line in lines[3:]]
    assert all(len(row) == 8 and row[0] == 'receipt' for row in rows), 'malformed physical receipt'
    assert int(count[1]) == len(rows), 'effect/receipt atomic count mismatch'
    assert len({row[1] for row in rows}) == len(rows), 'duplicate physical invocation'
    assert len({row[7] for row in rows}) == len(rows), 'duplicate physical receipt ID'
    if rows:
        assert rows[-1][6] == value[1], 'last effect and original receipt value differ'
    return {'present': True, 'count': int(count[1]), 'rows': rows, 'value': value[1]}


def journal(directory):
    lines = (directory / 'task.db').read_text().splitlines()
    assert lines and lines[0] == 'CORE_TASK_V1', 'invalid task journal header'
    fields = {}
    for line in lines[1:]:
        key, separator, value = line.partition('\t')
        assert separator and key not in fields, 'malformed/duplicate task journal field'
        fields[key] = value
    return fields


class AgentProcessTests(unittest.TestCase):
    serial = 0

    def new_directory(self):
        type(self).serial += 1
        return EVIDENCE / f'{self._testMethodName}-{self.serial}'

    def record(self, command, result):
        with (EVIDENCE / 'commands.jsonl').open('a') as stream:
            stream.write(json.dumps({'argv': command, 'exit': result.returncode,
                                     'stdout': result.stdout, 'stderr': result.stderr}) + '\n')

    def command(self, operation, directory, *options, code=0):
        command = [str(BINARY), operation, '--dir', str(directory), *map(str, options)]
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        self.record(command, result)
        self.assertEqual(result.returncode, code, (command, result.stdout, result.stderr))
        if code == 0:
            value = observation(result.stdout)
            self.assertIn('status', value)
            return value
        self.assertIn('error=', result.stderr)
        return result

    def start(self, directory, script='happy.tsv', **facts):
        aliases = {'read_only': 'read-only', 'ask': 'ask-every-time', 'full_allow': 'full-allow'}
        args = ['--script', str(LAB / 'fixtures' / script), '--input', 'synthetic user input']
        for key, value in facts.items():
            if key == 'tool_failure':
                if value:
                    args += ['--tool-behavior', 'fail']
                continue
            if key == 'mode':
                value = aliases.get(value, value)
            if isinstance(value, bool):
                value = str(value).lower()
            args += ['--' + key.replace('_', '-'), str(value)]
        return self.command('start', directory, *args)

    def assert_effects(self, directory, expected):
        state = physical(directory)
        self.assertEqual(state['count'], expected)
        return state

    def pause(self, directory, boundary):
        args = [str(BINARY), 'run', '--dir', str(directory), '--checkpoint', boundary]
        process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, bufsize=1)
        self.addCleanup(self.reap, process)
        selector = selectors.DefaultSelector()
        try:
            selector.register(process.stdout, selectors.EVENT_READ)
            self.assertTrue(selector.select(timeout=20), f'no flushed {boundary} checkpoint')
            line = process.stdout.readline()
            self.assertEqual(line.strip(), f'checkpoint={boundary}', f'checkpoint mismatch: {line!r}')
        finally:
            selector.close()
        return process

    @staticmethod
    def reap(process):
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=10)

    def kill_at(self, directory, boundary):
        process = self.pause(directory, boundary)
        process.kill()
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, -signal.SIGKILL)
        with (EVIDENCE / 'checkpoints.jsonl').open('a') as stream:
            stream.write(json.dumps({'boundary': boundary, 'exit': process.returncode,
                                     'stdout_after_checkpoint': stdout, 'stderr': stderr}) + '\n')

    def test_independently_authored_policy_and_provider_cases(self):
        cases = json.loads((LAB / 'fixtures/independent-cases.json').read_text())['cases']
        for case in cases:
            with self.subTest(case=case['id']):
                directory = self.new_directory()
                if case['id'] in {'unknown-tool', 'forged-extra-fields'}:
                    self.command('start', directory, '--script', LAB / 'fixtures' / case['script'], code=2)
                    self.assert_effects(directory, 0)
                    continue
                self.start(directory, case['script'], **case['host'])
                actual = self.command('run', directory)
                expected = case['assertions']  # Oracle only after actual execution.
                state = self.assert_effects(directory, expected['effects'])
                if 'answer' in expected:
                    self.assertEqual(bytes.fromhex(actual['answer_hex']).decode(), expected['answer'])
                    self.assertEqual(actual['status'], 'completed')
                if 'original_value' in expected:
                    self.assertEqual(bytes.fromhex(state['value']).decode(), expected['original_value'])
                if expected.get('success_answer') is False:
                    self.assertNotEqual(actual['status'], 'completed')
                    self.assertEqual(actual['answer_hex'], '')
                if expected.get('risk_asks') == 0:
                    self.assertEqual(actual['confirmations'], '0')
                if expected['effects']:
                    self.assertTrue(actual['receipt'])
                    self.assertEqual(actual['receipt'], state['rows'][0][7])

    def test_verified_physical_tool_context_drives_following_answer(self):
        directory = self.new_directory()
        self.start(directory, 'context-roles.tsv', mode='full_allow')
        actual = self.command('run', directory)
        state = self.assert_effects(directory, 1)
        row = state['rows'][0]
        self.assertEqual(bytes.fromhex(actual['answer_hex']).decode(),
                         f'answer sees receipt={row[7]};value=tool-result-data')
        context = bytes.fromhex(journal(directory)['context_hex']).decode()
        self.assertIn('user', context)
        self.assertIn('assistant', context)
        self.assertIn('tool', context)
        self.assertIn(row[7], context)
        self.assertEqual(row[2:4], [actual['task'], actual['attempt']])

    def test_confirmation_is_current_and_cannot_fix_hard_denial(self):
        for mode in ['ask', 'auto']:
            with self.subTest(mode=mode):
                directory = self.new_directory()
                self.start(directory, mode=mode, risk='high')
                waiting = self.command('run', directory)
                self.assertEqual(waiting['status'], 'waiting')
                self.assert_effects(directory, 0)
                repeated = self.command('run', directory)
                self.assertEqual(repeated['model_calls'], waiting['model_calls'])
                denied = self.command('run', directory, '--confirmed', 'true', '--scope-ok', 'false')
                self.assert_effects(directory, 0)
                self.assertNotEqual(denied['status'], 'completed')

    def test_current_host_fact_revalidation_all_hard_gates_and_modes(self):
        for mode in ['read_only', 'ask', 'auto', 'full_allow']:
            for flag, value in [('hard-ok', 'false'), ('revoked', 'true'),
                                ('scope-ok', 'false'), ('classification-ok', 'false')]:
                with self.subTest(mode=mode, gate=flag):
                    directory = self.new_directory()
                    self.start(directory, mode=mode, risk='high', confirmed=True)
                    actual = self.command('run', directory, '--' + flag, value)
                    self.assert_effects(directory, 0)
                    self.assertNotEqual(actual['status'], 'completed')

    def test_full_allow_taint_new_destination_adds_no_risk_confirmation(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow', risk='high', tainted=True, new_destination=True)
        actual = self.command('run', directory)
        self.assertEqual(actual['status'], 'completed')
        self.assertEqual(actual['confirmations'], '0')
        self.assert_effects(directory, 1)

    def test_confirmation_consumed_for_only_one_invocation(self):
        directory = self.new_directory()
        self.start(directory, 'two-effects.tsv', mode='ask', confirmed=True)
        waiting = self.command('run', directory)
        self.assertEqual(waiting['status'], 'waiting')
        self.assert_effects(directory, 1)
        original = physical(directory)['rows'][0][7]
        self.command('run', directory)
        self.assert_effects(directory, 1)
        completed = self.command('run', directory, '--confirmed', 'true')
        self.assertEqual(completed['status'], 'completed')
        state = self.assert_effects(directory, 2)
        self.assertEqual(state['rows'][0][7], original)

    def test_cancel_before_run_has_zero_calls_and_effects(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        actual = self.command('cancel', directory)
        self.assertEqual(actual['status'], 'cancelled')
        later = self.command('run', directory)
        self.assertEqual(later['model_calls'], '0')
        self.assertEqual(later['answer_hex'], '')
        self.assert_effects(directory, 0)

    def test_cancel_at_dispatch_prevents_effect_without_claiming_prior_zero_dispatch(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        running = self.pause(directory, 'dispatch')
        self.command('cancel', directory)
        running.stdin.write('\n')
        running.stdin.flush()
        stdout, stderr = running.communicate(timeout=20)
        self.assertEqual(running.returncode, 0, stderr)
        self.assert_effects(directory, 0)
        actual = observation(stdout)
        self.assertEqual(actual['answer_hex'], '')
        self.assertNotEqual(actual['status'], 'completed')

    def test_cancel_after_commit_preserves_original_receipt_and_stops_model(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        running = self.pause(directory, 'effect')
        before = self.assert_effects(directory, 1)
        self.command('cancel', directory)
        running.stdin.write('\n')
        running.stdin.flush()
        stdout, stderr = running.communicate(timeout=20)
        self.assertEqual(running.returncode, 0, stderr)
        actual = observation(stdout)
        self.assertEqual(actual['model_calls'], '1')
        self.assertEqual(actual['answer_hex'], '')
        self.assertEqual(actual['receipt'], before['rows'][0][7])
        self.assert_effects(directory, 1)
        again = self.command('run', directory)
        self.assertEqual(again['model_calls'], '1')
        self.assertEqual(again['receipt'], actual['receipt'])

    def test_sigkill_after_dispatch_keeps_notfound_unknown_and_never_replays(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        self.kill_at(directory, 'dispatch')
        self.assert_effects(directory, 0)
        baseline = self.command('inspect', directory)
        for operation in ['run', 'lookup', 'run']:
            actual = self.command(operation, directory)
            self.assertEqual(actual['status'], 'outcome_unknown')
            self.assertEqual(actual['model_calls'], baseline['model_calls'])
            self.assertEqual(actual['invocation'], baseline['invocation'])
            self.assert_effects(directory, 0)

    def test_sigkill_after_effect_original_receipt_then_followup_no_second_effect(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        self.kill_at(directory, 'effect')
        original = self.assert_effects(directory, 1)
        unresolved = self.command('run', directory)
        self.assertEqual(unresolved['status'], 'outcome_unknown')
        self.assertEqual(unresolved['model_calls'], '1')
        looked = self.command('lookup', directory)
        self.assertEqual(looked['receipt'], original['rows'][0][7])
        self.assertEqual(physical(directory), original)
        completed = self.command('run', directory)
        self.assertEqual(completed['status'], 'completed')
        self.assertEqual(completed['receipt'], original['rows'][0][7])
        self.assertEqual(physical(directory), original)

    def test_sigkill_after_projection_does_not_repeat_provider_or_effect(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        self.kill_at(directory, 'projection')
        original = self.assert_effects(directory, 1)
        completed = self.command('run', directory)
        self.assertEqual(completed['status'], 'completed')
        self.assertEqual(completed['model_calls'], '2')
        self.assertEqual(physical(directory), original)

    def test_missing_or_corrupt_effect_store_stays_unknown_never_reseeds(self):
        for mutation in ['missing', 'corrupt']:
            with self.subTest(mutation=mutation):
                directory = self.new_directory()
                self.start(directory, mode='full_allow')
                self.kill_at(directory, 'effect')
                effect = directory / 'effects.db'
                original = effect.read_bytes()
                (directory / 'original-effects-evidence.txt').write_bytes(original)
                if mutation == 'missing':
                    effect.rename(directory / 'effects-withheld-evidence.db')
                else:
                    effect.write_text('CORRUPT_SYNTHETIC_EVIDENCE\n')
                before = effect.read_bytes() if effect.exists() else None
                for operation in ['lookup', 'run']:
                    actual = self.command(operation, directory)
                    self.assertEqual(actual['status'], 'outcome_unknown')
                    self.assertEqual(actual['effects'], 'unknown')
                    self.assertEqual(actual['model_calls'], '1')
                self.assertEqual(effect.read_bytes() if effect.exists() else None, before)

    def test_response_loss_requires_lookup_before_further_provider_work(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow', tool_behavior='lose-response')
        unknown = self.command('run', directory)
        self.assertEqual(unknown['status'], 'outcome_unknown')
        original = self.assert_effects(directory, 1)
        self.assertEqual(self.command('run', directory)['model_calls'], '1')
        looked = self.command('lookup', directory)
        self.assertEqual(looked['receipt'], original['rows'][0][7])
        completed = self.command('run', directory)
        self.assertEqual(completed['status'], 'completed')
        self.assertEqual(physical(directory), original)

    def test_deterministic_io_fault_boundaries_no_fabricated_success(self):
        for boundary in ['dispatch', 'effect', 'projection']:
            with self.subTest(boundary=boundary):
                directory = self.new_directory()
                self.start(directory, mode='full_allow')
                result = subprocess.run([str(BINARY), 'run', '--dir', str(directory), '--io-fault', boundary],
                                        capture_output=True, text=True, timeout=20)
                self.record(['run', '--io-fault', boundary], result)
                self.assertIn(result.returncode, [0, 2])
                if result.returncode == 0:
                    self.assertNotEqual(observation(result.stdout)['status'], 'completed')
                self.assert_effects(directory, 1 if boundary == 'projection' else 0)
                # Reopening must not turn an uncertain operation into new execution.
                before = physical(directory)
                self.command('inspect', directory)
                self.command('lookup', directory)
                self.assertEqual(physical(directory), before)

    def test_persistent_step_and_call_budgets_do_not_reset(self):
        for option in ['max_steps', 'max_calls']:
            with self.subTest(option=option):
                directory = self.new_directory()
                self.start(directory, mode='full_allow', **{option: 1})
                stopped = self.command('run', directory)
                self.assertEqual(stopped['status'], 'budget_exhausted')
                self.assertEqual(stopped['model_calls'], '1')
                original = self.assert_effects(directory, 1)
                for operation in ['inspect', 'run', 'run']:
                    again = self.command(operation, directory)
                    for counter in ['steps', 'model_calls', 'context_bytes', 'output_bytes', 'total_units']:
                        self.assertEqual(again[counter], stopped[counter])
                self.assertEqual(physical(directory), original)

    def test_context_output_total_limits_prevent_effects_and_survive_reopen(self):
        for option in ['max_context', 'max_output', 'max_total']:
            with self.subTest(option=option):
                directory = self.new_directory()
                self.start(directory, mode='full_allow', **{option: 1})
                stopped = self.command('run', directory)
                self.assertEqual(stopped['status'], 'budget_exhausted')
                self.assert_effects(directory, 0)
                again = self.command('run', directory)
                self.assertEqual(again['status'], 'budget_exhausted')
                for counter in ['model_calls', 'steps', 'context_bytes', 'output_bytes', 'total_units']:
                    self.assertEqual(again[counter], stopped[counter])

    def test_invalid_limits_and_immutable_resume_overrides_reject(self):
        for option in ['max-steps', 'max-calls', 'max-context', 'max-output', 'max-total']:
            for value in ['0', '-1', '1000001', '18446744073709551616']:
                with self.subTest(option=option, value=value):
                    directory = self.new_directory()
                    self.command('start', directory, '--script', LAB / 'fixtures/happy.tsv', '--'+option, value, code=2)
                    self.assert_effects(directory, 0)
        directory = self.new_directory()
        self.start(directory, mode='full_allow', max_calls=1)
        self.command('run', directory, '--max-calls', '100', code=2)
        self.assertEqual(self.command('inspect', directory)['model_calls'], '0')

    def test_strict_malformed_provider_events_reject_before_execution(self):
        for script in ['malformed-hex.tsv', 'odd-hex.tsv', 'malformed-utf8.tsv', 'extra-answer.tsv']:
            with self.subTest(script=script):
                directory = self.new_directory()
                self.command('start', directory, '--script', LAB / 'fixtures' / script, code=2)
                self.assert_effects(directory, 0)

    def test_completed_task_reopen_preserves_receipt_and_counters(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        completed = self.command('run', directory)
        original = self.assert_effects(directory, 1)
        for operation in ['inspect', 'lookup', 'run']:
            actual = self.command(operation, directory)
            self.assertEqual(actual['task'], completed['task'])
            self.assertEqual(actual['attempt'], completed['attempt'])
            self.assertEqual(actual['receipt'], completed['receipt'])
            self.assertEqual(actual['model_calls'], completed['model_calls'])
            self.assertEqual(physical(directory), original)

    def test_exclusive_owner_rejects_competing_process_and_sigkill_releases(self):
        directory = self.new_directory()
        self.start(directory, mode='full_allow')
        running = self.pause(directory, 'dispatch')
        self.command('run', directory, code=2)
        self.assert_effects(directory, 0)
        running.kill()
        running.communicate(timeout=10)
        actual = self.command('run', directory)
        self.assertEqual(actual['status'], 'outcome_unknown')
        self.assert_effects(directory, 0)


def main():
    global BINARY, EVIDENCE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True)
    parser.add_argument('--evidence-dir', required=True)
    args = parser.parse_args()
    BINARY = Path(args.binary).resolve(strict=True)
    EVIDENCE = Path(args.evidence_dir).resolve()
    if EVIDENCE.is_relative_to(LAB):
        raise ValueError('evidence must be external to the lab')
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    assert os.access(BINARY, os.X_OK), 'binary must be executable'
    source_sha = subprocess.check_output(['git', '-C', str(LAB), 'rev-parse', 'HEAD'], text=True).strip()
    metadata = {'source_sha': source_sha, 'binary_sha256': hashlib.sha256(BINARY.read_bytes()).hexdigest(),
                'fixture_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((LAB/'fixtures').iterdir()) if p.is_file()},
                'scope': 'actual offline synthetic Rust process; no model/network/native/product acceptance'}
    (EVIDENCE/'identity.json').write_text(json.dumps(metadata, indent=2)+'\n')
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(AgentProcessTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    summary = {**metadata, 'methods': result.testsRun, 'failures': len(result.failures),
               'errors': len(result.errors), 'success': result.wasSuccessful()}
    (EVIDENCE/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps({k:summary[k] for k in ['source_sha','binary_sha256','methods','failures','errors','success']}))
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == '__main__':
    main()
