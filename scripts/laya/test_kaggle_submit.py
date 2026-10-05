"""Credential and notebook checks. No network and no token."""

import json
import tempfile
import unittest
from pathlib import Path

import kaggle_notebook
import kaggle_submit


class SubmitGuards(unittest.TestCase):
    def test_gate_failure_does_not_open_the_env_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            metrics = root / "stage1-metrics.json"
            metrics.write_text(json.dumps({"gate1b": "fail"}), encoding="utf-8")
            missing = root / "absent.env"
            with self.assertRaises(SystemExit) as caught:
                kaggle_submit.submit(metrics=metrics, env_file=missing)
            self.assertIn("GATE1b fail", str(caught.exception))
            self.assertFalse(missing.exists())

    def test_missing_metrics_stop_before_the_env_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing_metrics = Path(tmp) / "no-metrics.json"
            missing_env = Path(tmp) / "absent.env"
            with self.assertRaises(SystemExit) as caught:
                kaggle_submit.submit(metrics=missing_metrics, env_file=missing_env)
            self.assertIn("stage1b metrics missing", str(caught.exception))

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
