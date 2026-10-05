"""Credential and notebook checks. No network and no token."""

import json
import tempfile
import unittest
from pathlib import Path

import kaggle_notebook
import kaggle_submit


class SubmitGuards(unittest.TestCase):
    def test_a_write_target_stops_before_the_env_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            train = root / "train_set.jsonl"
            train.write_text(
                json.dumps({
                    "id": "train-0001",
                    "expected": "knowledge.delete",
                    "state": {"request": "删掉这份档案"},
                    "questions": {"tool": {"criteria": {"none": "没有"}}},
                }) + "\n",
                encoding="utf-8",
            )
            overlap = root / "train_overlap.json"
            overlap.write_text(
                json.dumps({
                    "exactEvalMatches": 0,
                    "nearDuplicatesAtOrAbove0.5": 0,
                    "maxEvalJaccard": 0.2,
                    "heldOutLeaks": [],
                }),
                encoding="utf-8",
            )
            missing = root / "absent.env"
            with self.assertRaises(SystemExit) as caught:
                kaggle_submit.submit(
                    env_file=missing,
                    train_path=train,
                    overlap_path=overlap,
                    selection_path=kaggle_submit.stage2_data.SELECTION,
                )
            self.assertIn("not read-only", str(caught.exception))
            self.assertFalse(missing.exists())

    def test_missing_overlap_stops_before_the_env_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            train = root / "train_set.jsonl"
            train.write_text("{}\n", encoding="utf-8")
            missing_env = root / "absent.env"
            with self.assertRaises(SystemExit) as caught:
                kaggle_submit.submit(
                    env_file=missing_env,
                    train_path=train,
                    overlap_path=root / "no-overlap.json",
                    selection_path=kaggle_submit.stage2_data.SELECTION,
                )
            self.assertIn("overlap report missing", str(caught.exception))
            self.assertFalse(missing_env.exists())

    def test_real_training_reaches_the_token_check_without_a_gate1b_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            env_file = Path(tmp) / "empty.env"
            env_file.write_text("OTHER_SECRET=leave-this\n", encoding="utf-8")
            with self.assertRaises(SystemExit) as caught:
                kaggle_submit.submit(env_file=env_file)
            self.assertIn("Kaggle-apikey is missing", str(caught.exception))

    def test_upload_omits_the_validation_split(self):
        rows = kaggle_submit.upload_rows(kaggle_submit.HERE / "train_set.jsonl")
        training, validation = kaggle_submit.gate.validation_split(
            kaggle_submit.gate.load_jsonl(kaggle_submit.HERE / "train_set.jsonl")
        )
        self.assertEqual([row["id"] for row in rows], [row["id"] for row in training])
        self.assertGreaterEqual(len(rows), 1000)
        self.assertTrue(validation)
        self.assertTrue({row["id"] for row in rows}.isdisjoint({row["id"] for row in validation}))

    def test_read_token_uses_only_the_named_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sample.env"
            path.write_text(
                'OTHER_SECRET=KGAT_should_not_be_read\nexport Kaggle-apikey="KGAT_exampletoken"\n',
                encoding="utf-8",
            )
            self.assertEqual(kaggle_submit.read_token(path), "KGAT_exampletoken")

    def test_non_kgat_value_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sample.env"
            path.write_text("Kaggle-apikey=not-a-token\n", encoding="utf-8")
            with self.assertRaises(SystemExit):
                kaggle_submit.read_token(path)

    def test_scrub_removes_a_token(self):
        self.assertNotIn("KGAT_exampletoken", kaggle_submit.scrub("denied KGAT_exampletoken"))
        self.assertIn("redacted", kaggle_submit.scrub("denied KGAT_exampletoken"))


class Notebook(unittest.TestCase):
    def test_notebook_embeds_the_training_script_and_disables_hub_push(self):
        document = kaggle_notebook.notebook()
        blob = json.dumps(document)
        for banned in (
            "LocalLLaMA",
            "typed-decisions",
            "HfApi",
            "push_to_hub",
            "HF_TOKEN",
            "KGAT_",
            "Kaggle-apikey",
        ):
            self.assertNotIn(banned, blob)
        self.assertIn(kaggle_notebook.REVISION, blob)
        self.assertIn("laya==0.3.27", blob)
        self.assertIn("NO_HUB_PUSH", blob)
        self.assertIn("n_gpu < 2", blob)
        self.assertIn("train_set.jsonl", blob)
        train_cell = next(cell["source"] for cell in document["cells"] if 'r"""' in cell["source"])
        self.assertIn('cfg["head_max_len"] = 512', train_cell)
        start = train_cell.index('r"""') + 4
        end = train_cell.rindex('"""')
        self.assertEqual(train_cell[start:end], kaggle_notebook.TRAIN.read_text(encoding="utf-8"))
        disk = json.loads(kaggle_notebook.NOTEBOOK.read_text(encoding="utf-8"))
        self.assertEqual(disk, document)
        self.assertGreaterEqual(len(kaggle_submit.DATASET_TITLE), 6)
        self.assertLessEqual(len(kaggle_submit.DATASET_TITLE), 50)
        self.assertGreaterEqual(len(kaggle_submit.DATASET_SLUG), 6)
        self.assertLessEqual(len(kaggle_submit.KERNEL_TITLE), 50)


if __name__ == "__main__":
    unittest.main()
