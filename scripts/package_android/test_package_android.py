"""Offline tests for local keyless Android packaging. No SDK download, no real build."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'package_android', Path(__file__).with_name('package_android.py')
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class PackageAndroidTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        (self.repo / 'apps' / 'muyon' / 'android').mkdir(parents=True)
        (self.repo / 'apps' / 'muyon' / 'pubspec.yaml').write_text('name: muyon\n')
        self.sdk = self.root / 'sdk'
        self._make_minimal_sdk(self.sdk)
        self.out = self.root / 'out'
        self.build_sha = 'a' * 40
        self.flutter_calls: list[tuple[str, ...]] = []
        self.env = patch.dict(os.environ, {
            'ANDROID_HOME': str(self.sdk),
            'ANDROID_SDK_ROOT': str(self.sdk),
        }, clear=False)
        self.env.start()
        self.addCleanup(self.env.stop)

    def _make_minimal_sdk(self, sdk: Path, with_ndk: bool = True):
        (sdk / 'platform-tools').mkdir(parents=True)
        (sdk / 'platforms' / 'android-35').mkdir(parents=True)
        build_tools = sdk / 'build-tools' / '35.0.0'
        build_tools.mkdir(parents=True)
        (build_tools / 'apksigner').write_text('#!/bin/sh\nexit 0\n')
        (build_tools / 'apksigner').chmod(0o755)
        if with_ndk:
            (sdk / 'ndk' / '27.0.12077973').mkdir(parents=True)
            (sdk / 'ndk' / '27.0.12077973' / 'source.properties').write_text(
                'Pkg.Revision=27.0.12077973\n'
            )

    def _write_apk(self, entry: str = 'classes.dex', dest: Path | None = None):
        path = dest or (
            self.repo / 'apps/muyon/build/app/outputs/flutter-apk/app-release.apk'
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(entry, b'fixture-apk-bytes')
        return path

    def fake_run(self, args, **kwargs):
        argv = tuple(str(a) for a in args)
        self.flutter_calls.append(argv)
        if argv[:2] == ('git', '-C') and argv[3:5] == ('rev-parse', 'HEAD'):
            return subprocess.CompletedProcess(args, 0, stdout=self.build_sha + '\n', stderr='')
        if argv[:3] == ('git', '-C', str(self.repo)) and 'status' in argv:
            return subprocess.CompletedProcess(args, 0, stdout='', stderr='')
        if 'flutter' in Path(argv[0]).name:
            if 'build' in argv and 'apk' in argv:
                self._write_apk()
                return subprocess.CompletedProcess(args, 0, stdout='Built build/app/outputs/flutter-apk/app-release.apk\n', stderr='')
            if 'pub' in argv and 'get' in argv:
                return subprocess.CompletedProcess(args, 0, stdout='', stderr='')
            if '--version' in argv:
                return subprocess.CompletedProcess(
                    args, 0,
                    stdout='{"frameworkVersion":"3.47.5","dartSdkVersion":"3.13.4"}\n',
                    stderr='',
                )
        if Path(argv[0]).name == 'apksigner' or argv[0].endswith('apksigner'):
            cert = (
                'Signer #1 certificate DN: CN=Android Debug, O=Android, C=US\n'
                'Signer #1 certificate SHA-256 digest: ' + ':'.join(['cc']*32) + '\n'
            )
            return subprocess.CompletedProcess(args, 0, stdout=cert, stderr='')
        if Path(argv[0]).name == 'java' or argv[0] == 'java':
            return subprocess.CompletedProcess(args, 0, stdout='openjdk version "17.0.0"\n', stderr='')
        if argv[0] == 'uname':
            return subprocess.CompletedProcess(args, 0, stdout='x86_64\n', stderr='')
        raise AssertionError(f'unexpected command: {argv}')

    def run_main(self, extra: list[str] | None = None):
        argv = [
            'package_android.py',
            '--repo', str(self.repo),
            '--output', str(self.out),
            '--flutter', 'flutter',
        ]
        if extra:
            argv.extend(extra)
        with patch.object(mod.subprocess, 'run', side_effect=self.fake_run):
            with patch.object(mod.shutil, 'which', side_effect=lambda name: name if name in {'flutter', 'java', 'git'} else None):
                return mod.main(argv)

    def test_missing_sdk_fails_without_download(self):
        os.environ.pop('ANDROID_HOME', None)
        os.environ.pop('ANDROID_SDK_ROOT', None)
        missing = self.root / 'no-sdk'
        downloads: list[str] = []

        def forbid_net(*args, **kwargs):
            downloads.append(str(args))
            raise AssertionError('must not download SDK')

        with patch.object(mod, 'resolve_android_home', return_value=None):
            with patch.object(mod.subprocess, 'run', side_effect=forbid_net):
                with self.assertRaisesRegex(SystemExit, 'Android SDK'):
                    mod.main([
                        'package_android.py',
                        '--repo', str(self.repo),
                        '--output', str(self.out),
                        '--flutter', 'flutter',
                    ])
        self.assertEqual(downloads, [])
        self.assertFalse(missing.exists())
        self.assertFalse(self.out.exists())

    def test_missing_ndk_fails_without_download(self):
        sdk = self.root / 'sdk-no-ndk'
        self._make_minimal_sdk(sdk, with_ndk=False)
        os.environ['ANDROID_HOME'] = str(sdk)
        os.environ['ANDROID_SDK_ROOT'] = str(sdk)
        downloads: list[str] = []

        def track(args, **kwargs):
            cmd = ' '.join(str(a) for a in args)
            if 'sdkmanager' in cmd or 'download' in cmd.lower():
                downloads.append(cmd)
            return self.fake_run(args, **kwargs)

        with patch.object(mod.subprocess, 'run', side_effect=track):
            with patch.object(mod.shutil, 'which', side_effect=lambda name: name if name in {'flutter', 'java', 'git'} else None):
                with self.assertRaisesRegex(SystemExit, 'NDK'):
                    mod.main([
                        'package_android.py',
                        '--repo', str(self.repo),
                        '--output', str(self.out),
                        '--flutter', 'flutter',
                        '--require-ndk',
                    ])
        self.assertEqual(downloads, [])
        self.assertFalse(self.out.exists())

    def test_dart_define_secrets_rejected(self):
        for flag in [
            '--dart-define=API_KEY=secret',
            '--dart-define=OPENAI_API_KEY=sk-test',
            '--dart-define=model_token=abc',
            '--dart-define=PASSWORD=x',
            '--dart-define-from-file=secrets.json',
        ]:
            with self.subTest(flag=flag):
                with self.assertRaisesRegex(SystemExit, 'dart-define|密钥|secret|keyless'):
                    self.run_main(['--', flag])
                self.assertFalse(self.out.exists())

    def test_any_dart_define_rejected_in_keyless_mode(self):
        with self.assertRaisesRegex(SystemExit, 'dart-define|keyless'):
            self.run_main(['--', '--dart-define=FEATURE_FLAG=1'])
        self.assertFalse(self.out.exists())

    def test_successful_package_names_and_manifest(self):
        code = self.run_main()
        self.assertEqual(code, 0)
        apk = self.out / f'muyon-android-{self.build_sha}-internal.apk'
        manifest_path = self.out / 'manifest.json'
        sha_path = self.out / f'muyon-android-{self.build_sha}-internal.apk.sha256'
        self.assertTrue(apk.is_file())
        self.assertTrue(manifest_path.is_file())
        self.assertTrue(sha_path.is_file())
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        self.assertEqual(sha_path.read_text().strip().split()[0], digest)
        manifest = json.loads(manifest_path.read_text())
        self.assertEqual(manifest['build_sha'], self.build_sha)
        self.assertEqual(manifest['platform'], 'android')
        self.assertEqual(manifest['signing']['method'], 'android-debug-key')
        self.assertTrue(manifest['internal_validation_only'])
        self.assertFalse(manifest['dart_defines'])
        self.assertEqual(manifest['files'][0]['sha256'], digest)
        self.assertEqual(manifest['files'][0]['path'], apk.name)
        # Build command must be release, no dart-define
        build_cmds = [c for c in self.flutter_calls if 'build' in c and 'apk' in c]
        self.assertEqual(len(build_cmds), 1)
        self.assertIn('--release', build_cmds[0])
        self.assertNotIn('--no-pub', build_cmds[0])
        self.assertTrue(all(not a.startswith('--dart-define') for a in build_cmds[0]))

    def test_apk_credential_path_rejected(self):
        def write_bad_apk(args, **kwargs):
            argv = tuple(str(a) for a in args)
            self.flutter_calls.append(argv)
            if 'flutter' in Path(argv[0]).name and 'build' in argv:
                self._write_apk('assets/keys/private.key')
                return subprocess.CompletedProcess(args, 0, stdout='', stderr='')
            return self.fake_run(args, **kwargs)

        with patch.object(mod.subprocess, 'run', side_effect=write_bad_apk):
            with patch.object(mod.shutil, 'which', side_effect=lambda name: name if name in {'flutter', 'java', 'git'} else None):
                with self.assertRaisesRegex(SystemExit, 'Credential|敏感|sensitive'):
                    mod.main([
                        'package_android.py',
                        '--repo', str(self.repo),
                        '--output', str(self.out),
                        '--flutter', 'flutter',
                    ])
        if self.out.exists():
            self.assertFalse(any(self.out.glob('*.apk')))

    def test_wrong_signature_rejected(self):
        def bad_signer(args, **kwargs):
            argv = tuple(str(a) for a in args)
            if Path(argv[0]).name == 'apksigner' or argv[0].endswith('apksigner'):
                return subprocess.CompletedProcess(
                    args, 0,
                    stdout='Signer #1 certificate DN: CN=Release\nSigner #1 certificate SHA-256 digest: ' + ('d' * 64),
                    stderr='',
                )
            return self.fake_run(args, **kwargs)

        with patch.object(mod.subprocess, 'run', side_effect=bad_signer):
            with patch.object(mod.shutil, 'which', side_effect=lambda name: name if name in {'flutter', 'java', 'git'} else None):
                with self.assertRaisesRegex(SystemExit, 'debug'):
                    mod.main([
                        'package_android.py',
                        '--repo', str(self.repo),
                        '--output', str(self.out),
                        '--flutter', 'flutter',
                    ])

    def test_invalid_build_sha_rejected(self):
        self.build_sha = 'DEADBEEF'
        with self.assertRaisesRegex(SystemExit, 'SHA|sha'):
            self.run_main()
        self.assertFalse(self.out.exists())

    def test_check_paths_rejects_secrets(self):
        for path in ['.env', 'keys/token', 'debug.keystore', 'rawlogs/x', 'a.pem', 'key.properties']:
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                mod.check_paths([path])

    def test_resolve_android_home_prefers_env(self):
        self.assertEqual(mod.resolve_android_home(), self.sdk.resolve())

    def test_no_network_helpers_exist(self):
        # Guard: script must not call sdkmanager or urllib for toolchains.
        source = Path(__file__).with_name('package_android.py').read_text()
        for forbidden in ['sdkmanager', 'urllib', 'requests.', 'wget', 'curl']:
            self.assertNotIn(forbidden, source)


if __name__ == '__main__':
    unittest.main()
