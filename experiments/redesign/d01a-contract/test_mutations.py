import tempfile
from pathlib import Path
import unittest
from mutation_runner import run_mutations


class MutationChecks(unittest.TestCase):
    def test_three_semantic_inverse_mutants_are_detected_by_named_assertions(self):
        with tempfile.TemporaryDirectory(prefix='d01a-mutation-test-') as tmp:
            results = run_mutations(Path(tmp))
        self.assertEqual({r['name'] for r in results}, {
            'bypass_actual_value_check', 'require_Auto_rule_in_FullAllow', 'downgrade_commercial_lineage'})
        for r in results:
            with self.subTest(mutant=r['name']):
                self.assertEqual(r['exit'], 1)
                self.assertGreater(r['assertion_failures'], 0)
                self.assertIn(r['required_failure_name'], r['failure_names'])


if __name__ == '__main__': unittest.main()
