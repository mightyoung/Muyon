from io import BytesIO
from pathlib import Path
import tempfile
import unittest
import zipfile
from model_package_gate import check_notices, REVIEWED_PROVENANCE_NOTICE, MODEL_NOTICE_NAMES


class ModelNoticePackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "source"
        self.assets = Path(self.temp.name) / "external"
        (self.source / "notices").mkdir(parents=True)
        (self.assets / "notices").mkdir(parents=True)
        self.contents = {"LOCAL_MODELS.txt": b"Project local model summary"}
        (self.source / "notices/LOCAL_MODELS.txt").write_bytes(self.contents["LOCAL_MODELS.txt"])
        for name in MODEL_NOTICE_NAMES:
            self.contents[name] = ("Complete reviewed text: " + name).encode()
            (self.assets / "notices" / name).write_bytes(self.contents[name])

    def archive(self, contents):
        buffer = BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for name, value in contents.items():
                archive.writestr("assets/notices/" + name, value)
        buffer.seek(0)
        return zipfile.ZipFile(buffer)

    def test_both_source_summary_and_distinct_reviewed_provenance_are_required(self):
        with self.archive(self.contents) as archive:
            result = check_notices(archive, self.assets, self.source)
        self.assertEqual(set(self.contents), {item["name"] for item in result})
        self.assertTrue(all(len(item["sha256"]) == 64 for item in result))
        for missing in ("LOCAL_MODELS.txt", REVIEWED_PROVENANCE_NOTICE):
            with self.subTest(missing=missing), self.archive({k: v for k, v in self.contents.items() if k != missing}) as archive:
                with self.assertRaisesRegex(AssertionError, "missing/duplicate packaged notice"):
                    check_notices(archive, self.assets, self.source)

    def test_changed_packaged_provenance_or_local_summary_cannot_pass(self):
        for changed in ("LOCAL_MODELS.txt", REVIEWED_PROVENANCE_NOTICE):
            with self.subTest(changed=changed), self.archive({**self.contents, changed: b"substitute"}) as archive:
                with self.assertRaisesRegex(AssertionError, "packaged notice bytes differ"):
                    check_notices(archive, self.assets, self.source)

    def test_legacy_external_name_and_empty_reviewed_notice_are_rejected(self):
        old = self.assets / "notices/LOCAL_MODELS.txt"
        old.write_bytes(b"colliding external provenance")
        with self.archive(self.contents) as archive, self.assertRaisesRegex(AssertionError, "collides with main"):
            check_notices(archive, self.assets, self.source)
        old.unlink()
        (self.assets / "notices" / REVIEWED_PROVENANCE_NOTICE).write_bytes(b" \n")
        with self.archive(self.contents) as archive, self.assertRaisesRegex(AssertionError, "missing/oversized notice"):
            check_notices(archive, self.assets, self.source)


if __name__ == "__main__":
    unittest.main()
