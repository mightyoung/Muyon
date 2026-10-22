import unittest
from instrumentation_gate import evaluate


GOOD = """INSTRUMENTATION_STATUS: numtests=1
INSTRUMENTATION_STATUS: class=ProductTest
INSTRUMENTATION_STATUS: test=actual
INSTRUMENTATION_STATUS_CODE: 0
OK (1 test)
"""


class ContentGateTest(unittest.TestCase):
    def test_actual_required_success(self):
        self.assertEqual("PASS", evaluate(GOOD, 0, {"ProductTest#actual"})["gate"])

    def test_false_success_cannot_be_hidden_by_adb_exit_or_summary(self):
        variants = [GOOD.replace("CODE: 0", "CODE: -2"),
                    GOOD.replace("CODE: 0", "CODE: -3"),
                    GOOD.replace("numtests=1", "numtests=2"),
                    GOOD.replace("OK (1 test)", ""), GOOD + "FAILURES!!!\n",
                    GOOD + GOOD]
        for variant in variants:
            with self.subTest(variant=variant):
                self.assertEqual("FAIL", evaluate(variant, 0, {"ProductTest#actual"})["gate"])
        self.assertEqual("FAIL", evaluate(GOOD, 0, {"Missing#case"})["gate"])
        self.assertEqual("FAIL", evaluate(GOOD, 1, {"ProductTest#actual"})["gate"])


if __name__ == "__main__":
    unittest.main()
