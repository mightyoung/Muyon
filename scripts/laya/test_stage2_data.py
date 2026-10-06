"""Leakage checks for the synthetic training set. No torch and no network."""

import json
import unittest
from pathlib import Path

import stage1_contract as contract
import stage2_data as data

HERE = Path(__file__).resolve().parent


class TrainingSet(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        selection = contract.load_json(data.SELECTION)
        glosses = contract.load_json(HERE / "glosses.json")["glosses"]
        cls.rows, cls.report = data.generate(selection, glosses, data.eval_prompts())
        cls.selection = selection

    def test_size_categories_and_seed(self):
        self.assertGreaterEqual(self.report["items"], 1000)
        self.assertEqual(self.report["seed"], 20261007)
        self.assertEqual(sum(self.report["byCategory"].values()), self.report["items"])
        for category, count in data.PLAN.items():
            self.assertEqual(self.report["generatedByCategory"][category], count)
        self.assertGreaterEqual(self.report["supplementRows"], 100)
        self.assertGreaterEqual(self.report["fullOptionRows"] * 2, self.report["items"])
        self.assertEqual(self.report["distinctRequests"], self.report["items"])
        self.assertEqual(self.report["descriptionCopiesAtOrAbove0.4"], 0)
        self.assertEqual(self.report["descriptionSpansAtOrAbove8"], 0)
        self.assertLess(self.report["maxDescriptionBigramJaccard"], 0.4)
        self.assertLess(self.report["maxDescriptionCommonSpan"], 8)
        self.assertGreaterEqual(self.report["distinctMaskedPatterns"], 800)

    def test_no_eval_copy_and_no_held_out_tool(self):
        self.assertEqual(self.report["exactEvalMatches"], 0)
        self.assertEqual(self.report["nearDuplicatesAtOrAbove0.5"], 0)
        self.assertLess(self.report["maxEvalJaccard"], 0.5)
        self.assertEqual(self.report["heldOutLeaks"], [])
        held = set(data.HELD_OUT_TOOLS)
        for row in self.rows:
            self.assertNotIn(row["expected"], held)
            blob = json.dumps(row["questions"], ensure_ascii=False)
            for tool_id in held:
                self.assertNotIn(tool_id, blob)

    def test_gold_is_one_hot_on_a_shown_option(self):
        for row in self.rows:
            criteria = row["questions"]["tool"]["criteria"]
            probs = row["gold"]["tool"]["probabilities"]
            self.assertEqual(set(criteria), set(probs))
            self.assertEqual(sum(probs.values()), 1.0)
            self.assertIn("none", criteria)
            offered = set(criteria) - {"none"}
            effects = {tool["id"]: tool["effect"] for tool in self.selection["tools"]}
            self.assertTrue(all(effects[tool_id] == "read" for tool_id in offered))
            if row["expected"] == "none":
                self.assertEqual(probs["none"], 1.0)
            else:
                self.assertEqual(probs["none"], 0.0)
                self.assertEqual(effects[row["expected"]], "read")
                self.assertNotIn(row["category"], {"none", "ambiguous", "urgent-write", "none-natural"})
            shown = criteria[row["expected"]]
            self.assertFalse(data.copies_option_text(row["state"]["request"], shown))

    def test_committed_file_matches_the_generator(self):
        path = HERE / "train_set.jsonl"
        disk = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
        self.assertEqual(disk, self.rows)


if __name__ == "__main__":
    unittest.main()
