import hashlib
from io import BytesIO
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from ci_model_inputs import download


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


if __name__ == "__main__":
    unittest.main()
