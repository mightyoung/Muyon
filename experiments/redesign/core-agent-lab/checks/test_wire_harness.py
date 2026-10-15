"""Independent harness/helper checks only, never Rust or real-provider evidence."""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from wire_process import assert_native_pair, wait_rust_ack

LAB = Path(__file__).resolve().parent.parent
HELPER = LAB / 'fixtures/wire/fake_service.py'
SCENARIOS = LAB / 'fixtures/wire/scenarios'


def requests():
    schema = {'type': 'object', 'properties': {'value': {'type': 'string'}},
              'required': ['value'], 'additionalProperties': False}
    first = {'model': 'fixture-model', 'stream': True, 'messages': [{'role': 'user', 'content': 'input'}],
             'tools': [{'type': 'function', 'function': {'name': 'fixture__record', 'parameters': schema}}]}
    second = deepcopy(first)
    second['messages'] += [
        {'role': 'assistant', 'content': None, 'tool_calls': [{'id': 'call_native_1', 'type': 'function',
          'function': {'name': 'fixture__record', 'arguments': '{"value":"wire-value"}'}}]},
        {'role': 'tool', 'tool_call_id': 'call_native_1',
         'content': '{"value":"wire-value","receipt":"physical-r1"}'}]
    return first, second


class WireHarnessTests(unittest.TestCase):
    def test_native_pair_oracle_accepts_exact_physical_pair(self):
        first, second = requests()
        assert_native_pair(first, second, 'wire-value', 'physical-r1')

    def test_native_pair_negatives_are_behavior_assertions(self):
        first, second = requests()
        mutants = []
        value = deepcopy(second); value['messages'][-1]['role'] = 'user'; mutants.append(value)
        value = deepcopy(second); value['messages'][-1]['tool_call_id'] = 'wrong'; mutants.append(value)
        value = deepcopy(second); value['messages'][-2].pop('tool_calls'); mutants.append(value)
        for mutant in mutants:
            with self.subTest(mutant=mutant), self.assertRaises(AssertionError):
                assert_native_pair(first, mutant, 'wire-value', 'physical-r1')

    def test_complete_history_rejects_conflicts_and_orphans_before_valid_tail(self):
        first, second = requests()
        original = deepcopy(second['messages'][-2:])
        mutants = []
        for field in ['arguments', 'receipt', 'result_value']:
            earlier = deepcopy(original)
            if field == 'arguments':
                earlier[0]['tool_calls'][0]['function']['arguments'] = '{"value":"forged-earlier-value"}'
                earlier[1]['content'] = '{"value":"forged-earlier-value","receipt":"invented-earlier-receipt"}'
            elif field == 'receipt':
                earlier[1]['content'] = '{"value":"wire-value","receipt":"invented-earlier-receipt"}'
            else:
                earlier[1]['content'] = '{"value":"wrong-result","receipt":"physical-r1"}'
            mutant = deepcopy(second); mutant['messages'][1:1] = earlier; mutants.append((field, mutant))
        mutant = deepcopy(second); mutant['messages'][1:1] = [deepcopy(original[1])]
        mutants.append(('orphan_tool', mutant))
        mutant = deepcopy(second); mutant['messages'][1:1] = [deepcopy(original[0])]
        mutants.append(('orphan_call', mutant))
        for label, mutant in mutants:
            with self.subTest(history=label), self.assertRaises(AssertionError):
                assert_native_pair(first, mutant, 'wire-value', 'physical-r1')

    def test_complete_history_accepts_identical_replay(self):
        first, second = requests()
        second['messages'][1:1] = deepcopy(second['messages'][-2:])
        assert_native_pair(first, second, 'wire-value', 'physical-r1')
        # Distinct later native calls retain the independently supplied earlier receipt.
        third = deepcopy(second)
        pair = deepcopy(second['messages'][-2:])
        pair[0]['tool_calls'][0]['id'] = 'call_native_2'
        pair[0]['tool_calls'][0]['function']['arguments'] = '{"value":"wire-second"}'
        pair[1]['tool_call_id'] = 'call_native_2'
        pair[1]['content'] = '{"value":"wire-second","receipt":"physical-r2"}'
        third['messages'] += pair
        assert_native_pair(first, third, 'wire-second', 'physical-r2', 'call_native_2',
                           physical_pairs={'call_native_1': ('wire-value', 'physical-r1'),
                                           'call_native_2': ('wire-second', 'physical-r2')})

    def test_helper_captures_actual_bytes_and_answer_depends_on_received_tool(self):
        _, second = requests()
        with TemporaryDirectory(prefix='wire-helper-selfcheck-') as temporary:
            captures = Path(temporary)
            original = json.dumps(second, ensure_ascii=False).encode()
            command = [sys.executable, '-B', str(HELPER), '--fixture-dir', str(SCENARIOS/'happy'),
                       '--turn', '2', '--capture-dir', str(captures)]
            result = subprocess.run(command, input=original, capture_output=True, timeout=10, check=True)
            self.assertEqual((captures/'request-2.json').read_bytes(), original)
            self.assertIn(b'physical-r1', result.stdout)
            self.assertIn(b'wire-value', result.stdout)
            changed = deepcopy(second)
            changed['messages'][-1]['content'] = '{"value":"different-real-input","receipt":"physical-r2"}'
            alternate = captures/'different'; alternate.mkdir()
            command[-1] = str(alternate)
            other = subprocess.run(command, input=json.dumps(changed).encode(), capture_output=True, timeout=10, check=True)
            self.assertNotEqual(result.stdout, other.stdout)
            self.assertIn(b'physical-r2', other.stdout)

    def test_helper_raw_response_matches_input_bytes_and_bad_config_fails(self):
        with TemporaryDirectory(prefix='wire-helper-raw-') as temporary:
            captures = Path(temporary)/'capture'
            command = [sys.executable,'-B',str(HELPER),'--fixture-dir',str(SCENARIOS/'happy'),
                       '--turn','1','--capture-dir',str(captures)]
            actual = subprocess.run(command,input=b'{"actual":"request"}',capture_output=True,check=True,timeout=10)
            self.assertEqual(actual.stdout,(SCENARIOS/'happy/turn-1.sse').read_bytes())
            self.assertEqual((captures/'emitted-1.sse').read_bytes(),actual.stdout)
            self.assertEqual((captures/'request-1.json').read_bytes(),b'{"actual":"request"}')
            invalid = Path(temporary)/'invalid';invalid.mkdir()
            (invalid/'config.json').write_text('{"format":"core-wire-service-v1","turns":[{"response":"x","oracle":true}]}')
            command[command.index('--fixture-dir')+1] = str(invalid)
            command[-1] = str(Path(temporary)/'rejected')
            rejected = subprocess.run(command,input=b'{}',capture_output=True,timeout=10)
            self.assertNotEqual(rejected.returncode,0)
            self.assertEqual(rejected.stdout,b'')

    def test_ack_harness_rejects_helper_flush_and_requires_consumption_marker(self):
        # Marker-only subprocess tests the checker handshake, not Rust consumption.
        for marker,valid in [('checkpoint=wire-args',True),('helper-flushed',False),('data: {}',False)]:
            code = 'import sys; print('+repr(marker)+',flush=True); sys.stdin.readline()'
            child = subprocess.Popen([sys.executable,'-u','-c',code],stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                if valid:
                    wait_rust_ack(child,'wire-args',timeout=2)
                    self.assertIsNone(child.poll())
                else:
                    with self.assertRaises(AssertionError):
                        wait_rust_ack(child,'wire-args',timeout=2)
            finally:
                child.kill();child.communicate(timeout=5)


if __name__ == '__main__':
    unittest.main(verbosity=2)
