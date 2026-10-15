"""Recorder checks use explicit fake byte echo; they are not product evidence."""
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest


class RecorderTests(unittest.TestCase):
    def test_exact_binary_roundtrip_and_reaped_child(self):
        with TemporaryDirectory(prefix='host-recorder-selfcheck-') as temporary:
            root = Path(temporary)
            echo = root / 'echo'
            echo.write_text('#!/usr/bin/python3\nimport sys\nb=sys.stdin.buffer.read()\nsys.stdout.buffer.write(b)\nsys.stderr.buffer.write(b"synthetic-stderr")\n')
            echo.chmod(0o700)
            evidence = root / 'evidence'
            payload = bytes(range(256)) * 600
            result = subprocess.run([
                sys.executable, str(Path(__file__).with_name('record_process.py')),
                '--binary', str(echo), '--evidence', str(evidence),
            ], input=payload, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, payload)
            self.assertEqual(result.stderr, b'synthetic-stderr')
            self.assertEqual((evidence / 'host.bin').read_bytes(), payload)
            self.assertEqual((evidence / 'core.bin').read_bytes(), payload)
            self.assertEqual((evidence / 'stderr.bin').read_bytes(), b'synthetic-stderr')
            self.assertEqual(json.loads((evidence / 'exit.json').read_text()), {'code': 0, 'reaped': True})
            launch = json.loads((evidence / 'launch.json').read_text())
            self.assertEqual(launch['binary'], str(echo))
            self.assertFalse(Path('/proc', str(launch['pid'])).exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
