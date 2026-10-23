"""Test-only projection checks; no model, network, JVM or production codec."""
from copy import deepcopy
from pathlib import Path
import unittest
import export_pipeline_values as exporter

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"

class PipelineValueExportChecks(unittest.TestCase):
    def setUp(self):
        self.fixture = exporter.load((FIXTURES / "public_pipeline.json").read_text(encoding="utf-8"))

    def test_projection_matches_committed_derivative(self):
        self.assertEqual(exporter.export(self.fixture), (FIXTURES / "public_pipeline.values.tsv").read_text(encoding="utf-8"))

    def test_versions_and_semantic_flags_cannot_be_defaulted(self):
        for key, value in [("contract_major", 2), ("schema_major", 2), ("fixture_revision", True),
                           ("synthetic", False), ("kotlin_api_frozen", True),
                           ("trusted_resolution_implemented", True)]:
            with self.subTest(key=key):
                changed = deepcopy(self.fixture)
                changed[key] = value
                with self.assertRaises(ValueError):
                    exporter.export(changed)

    def test_duplicate_json_keys_and_case_ids_are_rejected(self):
        with self.assertRaises(ValueError):
            exporter.load('{"synthetic":true,"synthetic":true}')
        changed = deepcopy(self.fixture)
        changed["compatibility_cases"].append(changed["compatibility_cases"][0])
        with self.assertRaises(ValueError):
            exporter.export(changed)

    def test_missing_unknown_and_wrong_descriptor_fields_fail(self):
        for action in ["missing", "unknown", "bool-dimension", "overflow", "missing-case-flag"]:
            with self.subTest(action=action):
                changed = deepcopy(self.fixture)
                descriptor = changed["compatibility_cases"][0]["index"]
                if action == "missing":
                    del descriptor["tokenizer_version"]
                elif action == "unknown":
                    descriptor["resolved"] = True
                elif action == "bool-dimension":
                    descriptor["dimensions"] = True
                elif action == "overflow":
                    descriptor["dimensions"] = 4294967296
                else:
                    del changed["compatibility_cases"][0]["expected_rust_compatible"]
                with self.assertRaises(ValueError):
                    exporter.export(changed)

    def test_null_empty_and_multibyte_values_are_lossless(self):
        rows = [line.split("\t") for line in exporter.export(self.fixture).splitlines()]
        candidates = {row[1]: row for row in rows if row[0] == "C"}
        self.assertEqual(candidates["missing-document"][2], "-")
        self.assertEqual(candidates["document-empty"][2], "")
        raw = bytes.fromhex(candidates["result-emoji-128"][3])
        self.assertEqual(len(raw), 128)
        self.assertEqual(raw.decode("utf-8", errors="strict"), "😀" * 32)
        self.assertEqual(bytes.fromhex(candidates["result-nul"][3]), b"r\0x")

    def test_u32_values_are_not_wrapped_into_jvm_int(self):
        rows = [line.split("\t") for line in exporter.export(self.fixture).splitlines()]
        descriptors = {row[1]: row for row in rows if row[0] == "D"}
        row = descriptors["same-dimensions-u32-max"]
        self.assertEqual(row[4], "4294967295")
        self.assertEqual(row[8], "4294967295")
        self.assertEqual(row[-2:], ["true", "false"])

    def test_whitespace_and_original_versions_are_not_normalized(self):
        rows = [line.split("\t") for line in exporter.export(self.fixture).splitlines()]
        descriptors = {row[1]: row for row in rows if row[0] == "D"}
        self.assertEqual(bytes.fromhex(descriptors["same-model-U+0085"][2]).decode("utf-8"), "\u0085")
        self.assertEqual(descriptors["same-model-U+0085"][-2], "false")
        self.assertEqual(descriptors["same-model-U+001C"][-2], "true")
        version = bytes.fromhex(descriptors["same-untrimmed-model_version"][2]).decode("utf-8")
        self.assertEqual(version, " synthetic-model-v1 ")

if __name__ == "__main__":
    unittest.main()
