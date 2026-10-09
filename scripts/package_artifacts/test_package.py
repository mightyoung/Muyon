"""Offline packaging guards and provenance tests; no native builds or real signing."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('package', Path(__file__).with_name('package.py'))
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.previous = Path.cwd()
        os.chdir(self.tmp.name)
        self.addCleanup(os.chdir, self.previous)
        self.addCleanup(self.tmp.cleanup)
        self.env = patch.dict(os.environ, {
            'TARGET_SHA': 'a' * 40, 'WORKFLOW_SHA': 'b' * 40,
            'WORKFLOW_REF': 'owner/repo/.github/workflows/package-artifacts.yml@refs/heads/task/test',
            'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '2', 'RUNNER_ARCH': 'X64',
            'ANDROID_HOME': str(Path('sdk').resolve()), 'ProgramFiles(x86)': 'tools',
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        self.signature = 'CN=Android Debug\nSigner #1 certificate SHA-256 digest: ' + 'c' * 64
        self.commands = patch.object(package, 'command', self.fake_command)
        self.commands.start()
        self.addCleanup(self.commands.stop)

    def file(self, name):
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'fixture')
        return path

    def fake_command(self, *args):
        if args[0] == 'git':
            return ('a' if args[2] == 'source' else 'b') * 40
        if args[0] == 'flutter':
            return '{"frameworkVersion":"fixture"}'
        if args[0] == 'dart':
            return 'Dart fixture'
        if args[0] == 'java':
            return 'Java fixture'
        if args[0].endswith('gradlew'):
            return 'Gradle fixture'
        if args[0].endswith('apksigner'):
            return self.signature
        if args[0] == 'codesign':
            return 'Signature=adhoc'
        if args[0] in {'xcodebuild', 'swift', 'cmake'}:
            return 'version fixture'
        if args[0].endswith('vswhere.exe'):
            return '[{"installationVersion":"fixture"}]'
        if args[0] == 'ditto':
            Path(args[-1]).write_bytes(b'archive fixture')
            return ''
        if args[0] == 'powershell':
            if 'Authenticode' in args[-1]:
                return 'NotSigned'
            raise AssertionError(args)
        raise AssertionError(args)

    def android(self, entry='classes.dex'):
        self.file('sdk/build-tools/35.0.0/apksigner')
        path = Path('source/apps/muyon/build/app/outputs/flutter-apk/app-release.apk')
        path.parent.mkdir(parents=True)
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(entry, b'fixture')

    def windows(self):
        root = 'source/apps/muyon/build/windows/x64/runner/Release/'
        for name in ['muyon.exe', 'flutter_windows.dll', 'data/icu.dat', 'data/app.so', 'data/flutter_assets/AssetManifest.bin']:
            self.file(root + name)

    def run_package(self, selected):
        os.environ['PACKAGE_PLATFORM'] = selected
        package.main()
        manifest = json.loads(Path('packages/manifest.json').read_text())
        artifact = Path('packages') / manifest['files'][0]['path']
        self.assertEqual(manifest['files'][0]['sha256'], hashlib.sha256(artifact.read_bytes()).hexdigest())
        self.assertEqual(manifest['source_sha'], 'a' * 40)
        self.assertEqual(manifest['workflow_sha'], 'b' * 40)
        self.assertEqual(manifest['run_attempt'], '2')
        self.assertEqual(len(list(Path('packages').iterdir())), 2)
        return manifest

    def test_android_provenance(self):
        self.android()
        self.assertEqual(self.run_package('android')['signing']['method'], 'android-debug-key')

    def test_macos_complete_bundle(self):
        root = 'source/apps/muyon/build/macos/Build/Products/Release/muyon.app/'
        self.file(root + 'Contents/MacOS/muyon')
        self.file(root + 'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS')
        self.assertEqual(self.run_package('macos')['signing']['method'], 'ad-hoc')

    def test_windows_complete_bundle(self):
        self.windows()
        self.assertEqual(self.run_package('windows')['signing']['method'], 'unsigned')
        archive_path = next(Path('packages').glob('*.zip'))
        with zipfile.ZipFile(archive_path) as archive:
            self.assertIn('Release/flutter_windows.dll', archive.namelist())
            self.assertIn('Release/data/flutter_assets/AssetManifest.bin', archive.namelist())

    def test_windows_missing_runtime_fails(self):
        self.windows()
        Path('source/apps/muyon/build/windows/x64/runner/Release/flutter_windows.dll').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Complete Windows'):
            self.run_package('windows')

    def test_source_mismatch_fails(self):
        os.environ['TARGET_SHA'] = 'd' * 40
        with self.assertRaisesRegex(RuntimeError, 'HEAD mismatch'):
            self.run_package('android')

    def test_wrong_android_signature_fails(self):
        self.android()
        self.signature = 'CN=Distribution'
        with self.assertRaisesRegex(RuntimeError, 'debug-signed'):
            self.run_package('android')

    def test_apk_embedded_key_fails(self):
        self.android('assets/keys/private.key')
        with self.assertRaisesRegex(RuntimeError, 'Credential'):
            self.run_package('android')

    def assert_apk_path_rejected(self, entry):
        self.android(entry)
        apk = Path('source/apps/muyon/build/app/outputs/flutter-apk/app-release.apk')
        with zipfile.ZipFile(apk) as archive:
            self.assertEqual(archive.namelist(), [entry])
            self.assertFalse(any(item.is_dir() for item in archive.infolist()))
        with self.assertRaisesRegex(RuntimeError, 'Credential'):
            self.run_package('android')

    def test_apk_rawlogs_directory_without_directory_entry_fails(self):
        self.assert_apk_path_rejected('assets/rawlogs/session.txt')

    def test_apk_keys_directory_without_directory_entry_fails(self):
        self.assert_apk_path_rejected('assets/keys/token.json')

    def test_zip_unsafe_paths_without_directory_entries_fail(self):
        entries = [
            '../token.json', 'assets/../token.json', 'assets/./../token.json',
            '/assets/token.json', '//server/share/token.json',
            r'C:\assets\token.json', 'C:token.json', r'\assets\token.json',
            r'assets\..\token.json', r'assets\KEYS\token.json',
            'assets/./RaWlOgS//session.txt', 'assets/file.txt:stream',
            'assets/line\nname.txt',
        ]
        with zipfile.ZipFile('unsafe.zip', 'w') as archive:
            for entry in entries:
                archive.writestr(entry, b'fixture')
        with zipfile.ZipFile('unsafe.zip') as archive:
            self.assertFalse(any(item.is_dir() for item in archive.infolist()))
            for entry in archive.namelist():
                with self.subTest(path=entry), self.assertRaises(RuntimeError):
                    package.check_paths([entry])
        with self.assertRaises(RuntimeError):
            package.check_paths(['assets/null\x00name'])

    def test_normal_zip_paths_pass(self):
        entries = ['classes.dex', 'assets/models/token.json', 'lib/arm64-v8a/libapp.so',
                   'assets/./fonts//font.ttf', r'data\flutter_assets\AssetManifest.bin']
        with zipfile.ZipFile('normal.zip', 'w') as archive:
            for entry in entries:
                archive.writestr(entry, b'fixture')
        with zipfile.ZipFile('normal.zip') as archive:
            package.check_paths(archive.namelist())
        package.check_paths(['assets/', 'Contents/Frameworks/FlutterMacOS.framework/'])
        self.android('assets/models/token.json')
        self.assertEqual(self.run_package('android')['signing']['method'], 'android-debug-key')

    def test_forbidden_output_paths(self):
        for path in ['.env', 'folder/debug.keystore', 'keys', 'rawlogs', 'test.log', 'key.properties']:
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                package.check_paths([path])


if __name__ == '__main__':
    unittest.main()
