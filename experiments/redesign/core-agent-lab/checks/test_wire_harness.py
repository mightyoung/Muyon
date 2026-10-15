"""Independent harness/helper checks only, never Rust or real-provider evidence."""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest

from wire_process import assert_native_pair

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


if __name__ == '__main__':
    unittest.main(verbosity=2)
