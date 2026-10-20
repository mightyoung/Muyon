import copy
import hashlib
import tempfile
import unittest
from pathlib import Path
from suite_gate import check


class SuiteProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "source"
        self.source.mkdir()
        (self.source / "OneTest.kt").write_text("package fixture\nclass OneTest {\n@Test fun succeeds() {}\n}\n")
        apk = root / "app.apk"
        test_apk = root / "test.apk"
        apk.write_bytes(b"app")
        test_apk.write_bytes(b"test")
        self.log = root / "run.log"
        self.log.write_text("INSTRUMENTATION_STATUS: numtests=1\nINSTRUMENTATION_STATUS: class=fixture.OneTest\nINSTRUMENTATION_STATUS: test=succeeds\nINSTRUMENTATION_STATUS_CODE: 0\nOK (1 test)\n")
        self.manifest = {"source_commit": "source", "build_id": "source:inputs", "apk": str(apk),
                         "test_apk": str(test_apk), "apk_sha256": hashlib.sha256(b"app").hexdigest(),
                         "test_apk_sha256": hashlib.sha256(b"test").hexdigest()}
        self.manifest["runs"] = [{"log": str(self.log), "log_sha256": hashlib.sha256(self.log.read_bytes()).hexdigest(),
                                  "adb_exit": 0, "required": ["fixture.OneTest#succeeds"],
                                  **{key: self.manifest[key] for key in ("build_id", "apk_sha256", "test_apk_sha256")}}]

    def test_passing_text_cannot_substitute_for_another_captured_log(self):
        self.assertEqual("PASS", check(self.manifest, self.source)["gate"])
        self.log.write_text(self.log.read_text() + "another passing run\n")
        with self.assertRaisesRegex(AssertionError, "run log changed"):
            check(self.manifest, self.source)

    def test_different_run_or_source_identity_is_refused(self):
        for key in ("build_id", "apk_sha256", "test_apk_sha256"):
            changed = copy.deepcopy(self.manifest)
            changed["runs"][0][key] = "different"
            with self.subTest(key=key), self.assertRaisesRegex(AssertionError, "identity differs"):
                check(changed, self.source)
        changed = copy.deepcopy(self.manifest)
        changed["source_commit"] = "different"
        with self.assertRaisesRegex(AssertionError, "source identity differs"):
            check(changed, self.source)


if __name__ == "__main__":
    unittest.main()
