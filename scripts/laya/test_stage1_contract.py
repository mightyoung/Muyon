"""Contract checks that do not load Laya."""

import unittest
from pathlib import Path

import stage1_contract as contract

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SELECTION = ROOT / "apps/muyon/lib/assistant/selection_eval/selection_set.json"


def _row(category, choice, expected, confidence, noul=0.9, dangerous=None):
    return {
        "id": f"{category}-{choice}-{expected}-{confidence}",
        "category": category,
        "choice": choice,
        "expected": expected,
        "confidence": confidence,
        "noulPTrue": noul,
        "dangerous": dangerous or ["knowledge.delete", "transfer.send"],
    }


class OptionText(unittest.TestCase):
    def test_glosses_cover_the_registered_tools_and_hide_ids(self):
        selection = contract.load_json(SELECTION)
        glosses = contract.load_json(HERE / "glosses.json")["glosses"]
        id_to_key, key_to_id, criteria = contract.build_options(selection["tools"], glosses)
        self.assertEqual(len(criteria), len(selection["tools"]) + 1)
        self.assertEqual(key_to_id["opt00"], "none")
        rendered = "\n".join(criteria.values())
        for tool in selection["tools"]:
            self.assertNotIn(tool["id"], rendered)
            self.assertNotIn(tool["id"], id_to_key[tool["id"]])
            self.assertIn(tool["description"], criteria[id_to_key[tool["id"]]])
            self.assertIn(glosses[tool["id"]], criteria[id_to_key[tool["id"]]])
        self.assertEqual(len(set(id_to_key.values())), len(id_to_key))

    def test_negation_set_does_not_copy_the_eval_prompts(self):
        selection = contract.load_json(SELECTION)
        items = contract.load_json(HERE / "negation_set.json")["items"]
        report = contract.validate_negation(
            items,
            selection["tools"],
            [task["prompt"] for task in selection["tasks"]],
        )
        self.assertGreaterEqual(report["items"], 12)
        self.assertLess(report["maxEvalJaccard"], 0.8)
        self.assertEqual(len(selection["tasks"]), 140)


class Scoring(unittest.TestCase):
    def test_threshold_rule_matches_the_d_r6_order(self):
        rows = [
            _row("exact", "knowledge.search", "knowledge.search", 0.99),
            _row("exact", "knowledge.delete", "knowledge.search", 0.99),
        ]
        threshold, _sweep = contract.choose_threshold(rows)
        self.assertEqual(threshold, 1.0)
        judged = contract.judge_row(rows[1], 0.95)
        self.assertTrue(judged["falseWrite"])
        self.assertFalse(contract.judge_row(rows[1], 1.0)["falseWrite"])

    def test_per_category_thresholds_keep_a_safe_category_usable(self):
        exact = [_row("exact", "inquiry.query", "inquiry.query", 0.60, dangerous=["knowledge.delete"]) for _ in range(3)]
        for index, row in enumerate(exact):
            row["id"] = f"exact-{index}"
        adversarial = [
            _row("adversarial", "knowledge.delete", "none", 0.99, dangerous=["knowledge.delete"])
            for _ in range(3)
        ]
        for index, row in enumerate(adversarial):
            row["id"] = f"adversarial-{index}"
        rows = exact + adversarial
        global_threshold, by_category, _sweep = contract.category_thresholds(rows, min_rows=3)
        self.assertEqual(global_threshold, 1.0)
        self.assertEqual(by_category["exact"]["threshold"], 0.6)
        self.assertEqual(by_category["adversarial"]["threshold"], 1.0)
        scored = contract.apply_category_thresholds(rows, global_threshold, by_category)
        self.assertEqual(scored["falseWrite"], 0)
        self.assertEqual(scored["top1"], 6)

    def test_noul_cut_is_raised_only_when_it_removes_false_writes_without_losing_hits(self):
        rows = []
        for index in range(3):
            rows.append(
                _row(
                    "exact",
                    "knowledge.search",
                    "knowledge.search",
                    0.99,
                    noul=0.9,
                    dangerous=["knowledge.delete"],
                )
            )
            rows[-1]["id"] = f"safe-{index}"
        for index in range(3):
            rows.append(
                _row(
                    "adversarial",
                    "knowledge.delete",
                    "none",
                    0.99,
                    noul=0.1,
                    dangerous=["knowledge.delete"],
                )
            )
            rows[-1]["id"] = f"trap-{index}"
        best, _table = contract.select_noul_threshold(rows, min_rows=3)
        self.assertGreater(best["noulThreshold"], 0.1)
        self.assertLessEqual(best["noulThreshold"], 0.9)
        self.assertEqual(best["falseWrite"], 0)
        self.assertEqual(best["top1"], 6)
        rewritten = contract.rewrite_noul(rows, best["noulThreshold"])
        self.assertTrue(all(row["noulDeclined"] for row in rewritten if row["id"].startswith("trap-")))
        self.assertTrue(all(not row["noulDeclined"] for row in rewritten if row["id"].startswith("safe-")))

    def test_gate_requires_held_out_adversarial_and_negation(self):
        self.assertTrue(contract.gate1(held_false_write=0, adversarial_false_write=0, negation_false_write=0))
        self.assertFalse(contract.gate1(held_false_write=0, adversarial_false_write=0, negation_false_write=1))
        self.assertFalse(contract.gate1(held_false_write=1, adversarial_false_write=0, negation_false_write=0))

    def test_split_matches_sorted_index(self):
        rows = [{"id": f"t{index:02d}", "category": "exact"} for index in range(6)]
        calibration, held = contract.split_calibration(list(reversed(rows)))
        self.assertEqual([row["id"] for row in calibration], ["t00", "t03"])
        self.assertEqual([row["id"] for row in held], ["t01", "t02", "t04", "t05"])


if __name__ == "__main__":
    unittest.main()
