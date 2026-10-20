"""Dummy bytes only; never opens a real env, invokes adb or contacts a provider."""
from contextlib import redirect_stdout, redirect_stderr
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import handoff_live_chat_credential as handoff

DUMMY = b'sk-offline-dummy-credential-00000000'


class LocalHandoffTests(unittest.TestCase):
    def test_explicit_literal_formats(self):
        for value in (DUMMY, b"'" + DUMMY + b"'", b'"' + DUMMY + b'"'):
            result = handoff.parse_key(bytearray(b'# dummy only\nOTHER=safe\nexport DEEPSEEK_API_KEY=' + value + b' # local\n'))
            self.assertEqual(DUMMY, result)
            result[:] = b'\0' * len(result)

    def test_duplicate_malformed_non_ascii_and_expansion_refused(self):
        for source in (b'DEEPSEEK_API_KEY=' + DUMMY + b'\nDEEPSEEK_API_KEY=' + DUMMY,
                       b'DEEPSEEK_API_KEY=$(no-execution)', b'DEEPSEEK_API_KEY=`no-execution`',
                       b'DEEPSEEK_API_KEY="unterminated', b'DEEPSEEK_API_KEY=has\\escape',
                       b'DEEPSEEK_API_KEY=space inside', b'DEEPSEEK_API_KEY=short',
                       b'NOT_AN_ASSIGNMENT', b'DEEPSEEK_API_KEY=\xff',
                       b'DEEPSEEK_API_KEY="' + DUMMY + b'" trailing', b'X=' + DUMMY,
                       b'DEEPSEEK_API_KEY=' + DUMMY + b'\0', b'x' * (handoff.MAX_SOURCE + 1)):
            with self.subTest(size=len(source)), self.assertRaises(handoff.Refused):
                handoff.parse_key(bytearray(source))

    def test_single_token_requires_utf8_and_exact_nontruncated_boundaries(self):
        result = handoff.parse_key(bytearray('仅限离线示例：'.encode() + DUMMY + b'\n'), True)
        self.assertEqual(DUMMY, result)
        for source in (b'none', DUMMY + b' ' + DUMMY, b'x' + DUMMY,
                       b'sk-' + b'a' * 129, b'\xff' + DUMMY):
            with self.assertRaises(handoff.Refused):
                handoff.parse_key(bytearray(source), True)

    def test_fixed_fd_guard_never_places_key_in_command(self):
        script = handoff.write_command(b'1:2:10000:600')
        self.assertIn('toybox timeout 5', script)
        self.assertLess(script.index('test -p /proc/self/fd/3'), script.index('cat >&3'))
        self.assertLess(script.index('stat -Lc'), script.index('cat >&3'))
        command = handoff.adb_command(script)
        self.assertIn(handoff.PACKAGE, command)
        self.assertIn('emulator-5554', command)
        self.assertNotIn(DUMMY.decode(), ' '.join(command))
        for identity in (b'1:2:3:666', b'1:2:3:600;echo unexpected'):
            with self.assertRaises(handoff.Refused):
                handoff.write_command(identity)

    def test_dry_run_reads_nothing_and_uses_no_device(self):
        stdout = io.StringIO()
        with mock.patch.object(handoff.os, 'open', side_effect=AssertionError('must not read a file')), \
                mock.patch.object(handoff, 'invoke', side_effect=AssertionError('must not invoke adb')), redirect_stdout(stdout):
            self.assertEqual(0, handoff.main(['--dry-run']))
        self.assertEqual('DRY_RUN_NO_SECRET_NO_DEVICE\n', stdout.getvalue())

    def test_dummy_transfer_only_stdin_and_wipes_retained_mutable_frame(self):
        frames = []
        def invoke(command, frame=None):
            self.assertNotIn(DUMMY.decode(), ' '.join(command))
            if frame is None:
                return b'1:2:10000:600\n'
            self.assertEqual(DUMMY + b'\n', frame)
            frames.append(frame)
            return b''
        with tempfile.TemporaryDirectory(prefix='dummy-handoff-test-') as root:
            source = Path(root) / 'dummy.env'
            source.write_bytes(b'DEEPSEEK_API_KEY=' + DUMMY)
            stdout = io.StringIO(); stderr = io.StringIO()
            with mock.patch.object(handoff, 'invoke', side_effect=invoke) as call, redirect_stdout(stdout), redirect_stderr(stderr):
                self.assertEqual(0, handoff.main(['--env', str(source)]))
                self.assertEqual(2, call.call_count)
            self.assertEqual('PIPE_SENT; INSTALL_NOT_VERIFIED\n', stdout.getvalue())
            self.assertEqual('', stderr.getvalue())
            self.assertTrue(frames and all(value == 0 for value in frames[0]))

    def test_source_open_refuses_fifo_symlink_directory_and_oversize(self):
        with tempfile.TemporaryDirectory(prefix='dummy-handoff-source-') as root:
            root = Path(root)
            regular = root / 'dummy.env'; regular.write_bytes(b'DEEPSEEK_API_KEY=' + DUMMY)
            fifo = root / 'dummy.fifo'; os.mkfifo(fifo)
            link = root / 'dummy.link'; link.symlink_to(regular)
            large = root / 'large.env'; large.write_bytes(b'x' * (handoff.MAX_SOURCE + 1))
            for path in (fifo, link, root, large):
                with self.subTest(kind=path.name), mock.patch.object(handoff.os, 'read', side_effect=AssertionError('special source must not be read')):
                    with self.assertRaises(handoff.Refused):
                        handoff.read_source(path)

    def test_timeout_is_one_attempt_and_fixed_error(self):
        child = mock.Mock()
        child.communicate.side_effect = [subprocess.TimeoutExpired('dummy-command', 8), (b'', b'')]
        child.poll.return_value = None
        with mock.patch.object(handoff.subprocess, 'Popen', return_value=child) as start:
            with self.assertRaisesRegex(handoff.Refused, '^local_credential_handoff_refused$'):
                handoff.invoke(['dummy-command'], bytearray(DUMMY))
            self.assertEqual(1, start.call_count)
            child.kill.assert_called_once()

    def test_interrupt_kills_and_reaps_adb_without_retry(self):
        child = mock.Mock()
        child.communicate.side_effect = [KeyboardInterrupt(), (b'', b'')]
        child.poll.return_value = None
        with mock.patch.object(handoff.subprocess, 'Popen', return_value=child) as start:
            with self.assertRaises(handoff.Refused):
                handoff.invoke(['dummy-command'], bytearray(DUMMY))
            self.assertEqual(1, start.call_count)
            child.kill.assert_called_once()
            self.assertEqual(2, child.communicate.call_count)


if __name__ == '__main__':
    unittest.main()
