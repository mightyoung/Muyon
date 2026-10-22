import hashlib
from io import BytesIO
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from ci_model_inputs import download, prepare, PREPARE
from model_package_gate import REVIEWED_PROVENANCE_NOTICE


class ModelInputDownloadTest(unittest.TestCase):
    def response(self, data, url="https://example.invalid/fixed"):
        response = BytesIO(data)
        response.geturl = lambda: url
        return response

    def test_verified_bytes_publish_and_no_partial_remains(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "model"
            with patch("urllib.request.urlopen", return_value=self.response(b"fixed")):
                download("https://example.invalid/fixed", target, 5, hashlib.sha256(b"fixed").hexdigest())
            self.assertEqual(b"fixed", target.read_bytes())
            self.assertFalse(target.with_suffix(".part").exists())

    def test_mismatch_and_oversize_preserve_previous_verified_file(self):
        for body, digest in [(b"wrong", hashlib.sha256(b"fixed").hexdigest()), (b"overlong", None)]:
            with self.subTest(body=body), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "model"
                target.write_bytes(b"previous")
                with patch("urllib.request.urlopen", return_value=self.response(body)):
                    with self.assertRaises(ValueError):
                        download("https://example.invalid/fixed", target, 5, digest)
                self.assertEqual(b"previous", target.read_bytes())
                self.assertFalse(target.with_suffix(".part").exists())

    def test_non_https_credentials_and_downgraded_redirect_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "model"
            for url in ["http://example.invalid/fixed", "https://user:secret@example.invalid/fixed"]:
                with self.assertRaises(ValueError):
                    download(url, target)
            with patch("urllib.request.urlopen", return_value=self.response(b"fixed", "http://example.invalid/fixed")):
                with self.assertRaises(ValueError):
                    download("https://example.invalid/fixed", target)
            self.assertFalse(target.exists())

    def test_reviewed_notice_has_distinct_asset_name_and_preserves_input(self):
        for legacy in (False, True):
            with self.subTest(legacy=legacy), tempfile.TemporaryDirectory() as directory:
                source, assets = Path(directory) / "source", Path(directory) / "assets"
                source.mkdir()
                (assets / "notices").mkdir(parents=True)
                notice = b"Reviewed model provenance and full applicable terms\n"
                (source / "LOCAL_MODELS.txt").write_bytes(notice)
                old = assets / "notices/LOCAL_MODELS.txt"
                if legacy:
                    old.write_bytes(notice)
                with patch.object(PREPARE, "prepare") as models:
                    prepare(source, assets)
                models.assert_called_once_with(source, assets, fetch_notices=False)
                self.assertEqual(notice, (source / "LOCAL_MODELS.txt").read_bytes())
                self.assertEqual(notice, (assets / "notices" / REVIEWED_PROVENANCE_NOTICE).read_bytes())
                self.assertFalse(old.exists())

    def test_conflicting_legacy_notice_is_not_silently_deleted(self):
        with tempfile.TemporaryDirectory() as directory:
            source, assets = Path(directory) / "source", Path(directory) / "assets"
            source.mkdir()
            (assets / "notices").mkdir(parents=True)
            (source / "LOCAL_MODELS.txt").write_bytes(b"new reviewed provenance")
            old = assets / "notices/LOCAL_MODELS.txt"
            old.write_bytes(b"different original terms must be preserved")
            with patch.object(PREPARE, "prepare"), self.assertRaisesRegex(ValueError, "Conflicting legacy"):
                prepare(source, assets)
            self.assertEqual(b"different original terms must be preserved", old.read_bytes())

    def test_official_fetch_needs_no_repository_variable_and_keeps_all_pins(self):
        with tempfile.TemporaryDirectory() as directory:
            source, assets = Path(directory) / "source", Path(directory) / "assets"
            (assets / "notices").mkdir(parents=True)
            with patch("ci_model_inputs.download") as downloaded, patch.object(PREPARE, "prepare") as models:
                prepare(source, assets, fetch=True)
            self.assertEqual(len(PREPARE.MODELS), downloaded.call_count)
            for name, (relative, size, digest) in PREPARE.MODELS.items():
                downloaded.assert_any_call(PREPARE.OFFICIAL_SOURCES[name], source / relative, size, digest)
            models.assert_called_once_with(source, assets, fetch_notices=True)
            notice = (assets / "notices" / REVIEWED_PROVENANCE_NOTICE).read_text()
            self.assertIn("2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135", notice)
            self.assertIn("58faf90940886df2d62be555c8765d00dac362c5", notice)
            self.assertIn("6f1bd4ac6c5df7444f9cca7ca36cafe6cfa34cd6f49fefb1e0b4be8143aed8bc", notice)
            self.assertIn("different artifact", notice)
            self.assertFalse((assets / "notices/LOCAL_MODELS.txt").exists())

    def test_existing_verified_official_input_is_reused_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "model"
            target.write_bytes(b"fixed")
            with patch("urllib.request.urlopen") as network:
                download("https://example.invalid/fixed", target, 5, hashlib.sha256(b"fixed").hexdigest())
            network.assert_not_called()
            self.assertEqual(b"fixed", target.read_bytes())

    def test_wrong_existing_model_is_never_overwritten_by_official_fetch(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "model"
            target.write_bytes(b"user's original artifact")
            with patch("urllib.request.urlopen") as network, self.assertRaisesRegex(ValueError, "Existing model input differs"):
                download("https://example.invalid/fixed", target, 5, hashlib.sha256(b"fixed").hexdigest())
            network.assert_not_called()
            self.assertEqual(b"user's original artifact", target.read_bytes())

    def test_corrupt_or_oversized_new_download_is_never_published(self):
        for body in (b"wrong", b"overlong"):
            with self.subTest(body=body), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "model"
                with patch("urllib.request.urlopen", return_value=self.response(body)), self.assertRaises(ValueError):
                    download("https://example.invalid/fixed", target, 5, hashlib.sha256(b"fixed").hexdigest())
                self.assertFalse(target.exists())
                self.assertFalse(target.with_suffix(".part").exists())


if __name__ == "__main__":
    unittest.main()
