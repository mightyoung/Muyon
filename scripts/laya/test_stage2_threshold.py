"""Re-weighted validation threshold. No model, no network, no .env."""

import unittest
from pathlib import Path

import stage1_contract as contract
import stage2_data as data
import stage2_threshold as gate

HERE = Path(__file__).resolve().parent


def _scored(expected, choice, confidence, dangerous=None):
    return {
        "category": "synthetic",
        "expected": expected,
        "choice": choice,
        "confidence": confidence,
        "dangerous": dangerous or [],
    }


class Mix(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.selection = contract.load_json(data.SELECTION)
        cls.tasks = cls.selection["tasks"]
        cls.tools = cls.selection["tools"]

    def test_answerable_subset_is_49_read_and_18_none(self):
        rows = gate.assert_answerable_mix(self.tasks, self.tools)
        counts = gate.target_mix(self.tasks, self.tools)
        self.assertEqual(len(rows), 67)
        self.assertEqual(counts, {
            "none|zh": 18,
            "read|en": 12,
            "read|mixed": 12,
            "read|zh": 25,
        })

    def test_training_file_withholds_a_validation_split_and_reports_english(self):
        rows = gate.load_jsonl(HERE / "train_set.jsonl")
        training, validation = gate.validation_split(rows)
        self.assertGreaterEqual(len(training), 1000)
        self.assertTrue(validation)
        self.assertEqual(len(training) + len(validation), len(rows))
        self.assertTrue({row["id"] for row in training}.isdisjoint({row["id"] for row in validation}))
        report = gate.reweight(
            validation,
            gate.target_mix(self.tasks, self.tools),
            text_of=lambda row: row["state"]["request"],
            expected_of=lambda row: row["expected"],
        )
        self.assertIn("read|zh", report["supported"])
        self.assertIn("read|mixed", report["supported"])
        self.assertIn("read|en", report["supported"])
        self.assertIn("none|zh", report["supported"])
        self.assertEqual(report["unmatchedTarget"], {})
        weighted = {}
        for key, weight in zip(report["keys"], report["weights"]):
            weighted[key] = weighted.get(key, 0.0) + weight
        total = sum(weighted.values())
        for key, share in report["renormalizedTargetShare"].items():
            self.assertAlmostEqual(weighted[key] / total, share)

    def test_reweight_prefers_the_read_rows_the_unweighted_fit_drops(self):
        rows = [
            _scored("none", "inquiry.search", 0.99),
            _scored("none", "inquiry.search", 0.99),
            _scored("none", "inquiry.search", 0.99),
            _scored("none", "inquiry.search", 0.99),
            _scored("none", "inquiry.search", 0.99),
            _scored("none", "inquiry.search", 0.99),
            _scored("knowledge.search", "knowledge.search", 0.99),
            _scored("knowledge.search", "knowledge.search", 0.99),
            _scored("knowledge.search", "knowledge.search", 1.0),
            _scored("knowledge.search", "knowledge.search", 1.0),
            _scored("none", "knowledge.delete", 0.1, ["knowledge.delete"]),
        ]
        unweighted, _sweep = contract.choose_threshold(rows)
        weights = [1, 1, 1, 1, 1, 1, 10, 10, 10, 10, 1]
        weighted, sweep = gate.choose_threshold_weighted(rows, weights)
        self.assertEqual(unweighted, 1.0)
        self.assertEqual(weighted, 0.95)
        chosen = next(point for point in sweep if point["threshold"] == weighted)
        self.assertEqual(chosen["falseWrite"], 0)

    def test_empty_weights_do_not_invent_a_low_threshold(self):
        rows = [_scored("knowledge.search", "knowledge.search", 0.2)]
        threshold, sweep = gate.choose_threshold_weighted(rows, [0.0])
        self.assertEqual(threshold, 1.0)
        self.assertEqual(sweep, [])


class Preconditions(unittest.TestCase):
    def test_a_write_target_is_rejected(self):
        tools = [{"id": "knowledge.search", "effect": "read"}, {"id": "knowledge.delete", "effect": "write"}]
        rows = [{
            "id": "train-0001",
            "expected": "knowledge.delete",
            "questions": {"tool": {"criteria": {"none": "x"}}},
        }]
        with self.assertRaises(ValueError) as caught:
            gate.assert_read_only_targets(rows, tools, {"ocr.recognize"})
        self.assertIn("not read-only", str(caught.exception))

    def test_overlap_must_stay_under_the_near_duplicate_bar(self):
        gate.assert_overlap({
            "exactEvalMatches": 0,
            "nearDuplicatesAtOrAbove0.5": 0,
            "maxEvalJaccard": 0.2174,
            "heldOutLeaks": [],
        })
        with self.assertRaises(ValueError):
            gate.assert_overlap({
                "exactEvalMatches": 0,
                "nearDuplicatesAtOrAbove0.5": 0,
                "maxEvalJaccard": 0.5,
                "heldOutLeaks": [],
            })


class OneStandardError(unittest.TestCase):
    def row(self, confidence, choice, expected):
        return {"confidence": confidence, "choice": choice, "expected": expected, "dangerous": []}

    def test_prefers_the_higher_threshold_within_noise(self):
        # Low threshold wins by one row out of 363; within one standard error
        # the higher threshold that abstains on the shaky pick is chosen.
        rows = [self.row(0.95, "a", "a") for _ in range(300)]
        rows += [self.row(0.95, "c", "a") for _ in range(60)]
        rows += [self.row(0.2, "a", "a") for _ in range(2)]
        rows += [self.row(0.2, "b", "none")]
        weights = [1.0] * len(rows)
        best, _ = gate.choose_threshold_weighted(rows, weights)
        chosen, _, stderr = gate.choose_threshold_one_se(rows, weights)
        self.assertLess(best, 0.25)
        self.assertGreater(chosen, best)
        self.assertGreater(stderr, 0)

    def test_a_clear_winner_is_kept(self):
        rows = [self.row(0.3, "a", "a") for _ in range(200)] + [self.row(0.95, "a", "a")]
        chosen, _, _ = gate.choose_threshold_one_se(rows, [1.0] * len(rows))
        self.assertLessEqual(chosen, 0.3)


if __name__ == "__main__":
    unittest.main()
