"""Offline packaging guards and provenance tests; no native builds or real signing."""
import hashlib
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile
from types import SimpleNamespace
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
        self.mac_signature = 'Signature=adhoc'
        self.windows_signature = 'NotSigned'
        self.fail_command = None
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
        if Path(args[0]).name == self.fail_command:
            raise subprocess.CalledProcessError(1, args)
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
            return self.mac_signature
        if args[0] in {'xcodebuild', 'swift', 'cmake'}:
            return 'version fixture'
        if args[0].endswith('vswhere.exe'):
            return '[{"installationVersion":"fixture"}]'
        if args[0] == 'ditto':
            Path(args[-1]).write_bytes(b'archive fixture')
            return ''
        if args[0] == 'powershell':
            if 'Authenticode' in args[-1]:
                return self.windows_signature
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

    def macos(self):
        root = Path('source/apps/muyon/build/macos/Build/Products/Release/muyon.app')
        self.file(root / 'Contents/MacOS/muyon')
        self.file(root / 'Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS')
        return root

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
        root = self.macos()
        (root / 'Contents/Frameworks/Current').symlink_to('FlutterMacOS.framework', target_is_directory=True)
        self.assertEqual(self.run_package('macos')['signing']['method'], 'ad-hoc')

    def test_windows_complete_bundle(self):
        self.windows()
        self.file('source/apps/muyon/build/windows/x64/runner/Release/native_assets/extra.dll').write_bytes(b'distinct extra runtime')
        self.assertEqual(self.run_package('windows')['signing']['method'], 'unsigned')
        archive_path = next(Path('packages').glob('*.zip'))
        with zipfile.ZipFile(archive_path) as archive:
            root = Path('source/apps/muyon/build/windows/x64/runner/Release')
            expected = {(Path('Release') / p.relative_to(root)).as_posix(): p.read_bytes()
                        for p in root.rglob('*') if p.is_file()}
            self.assertEqual(set(archive.namelist()), set(expected))
            for name, data in expected.items():
                self.assertEqual(archive.read(name), data)

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

    def test_sha_formats_fail_before_packaging(self):
        for variable in ['TARGET_SHA', 'WORKFLOW_SHA']:
            original = os.environ[variable]
            for invalid in ['develop', 'a' * 39, 'A' * 40, 'g' * 40, 'a' * 40 + '\n']:
                with self.subTest(variable=variable, value=invalid):
                    os.environ[variable] = invalid
                    with self.assertRaisesRegex(RuntimeError, 'Invalid .* SHA'):
                        self.run_package('android')
                    self.assertFalse(Path('packages').exists())
            os.environ[variable] = original

    def test_workflow_mismatch_fails_before_packaging(self):
        os.environ['WORKFLOW_SHA'] = 'c' * 40
        with self.assertRaisesRegex(RuntimeError, 'Workflow HEAD mismatch'):
            self.run_package('android')
        self.assertFalse(Path('packages').exists())

    def test_missing_macos_bundle_fails(self):
        with self.assertRaisesRegex(RuntimeError, 'exactly one'):
            self.run_package('macos')

    def test_multiple_macos_bundles_fail(self):
        root = self.macos()
        (root.parent / 'extra.app').mkdir()
        with self.assertRaisesRegex(RuntimeError, 'exactly one'):
            self.run_package('macos')

    def test_wrong_macos_signature_fails(self):
        self.macos()
        self.mac_signature = 'Authority=Developer ID Application'
        with self.assertRaisesRegex(RuntimeError, 'ad-hoc'):
            self.run_package('macos')

    def test_wrong_windows_signature_fails(self):
        self.windows()
        self.windows_signature = 'Valid'
        with self.assertRaisesRegex(RuntimeError, 'unsigned'):
            self.run_package('windows')

    def test_failed_apksigner_command_propagates(self):
        self.android()
        self.fail_command = 'apksigner'
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_package('android')
        self.assertFalse(Path('packages/manifest.json').exists())

    def test_failed_codesign_command_propagates(self):
        self.macos()
        self.fail_command = 'codesign'
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_package('macos')
        self.assertFalse(Path('packages/manifest.json').exists())

    def test_failed_windows_signature_command_propagates(self):
        self.windows()
        self.fail_command = 'powershell'
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_package('windows')
        self.assertFalse(Path('packages/manifest.json').exists())

    def test_windows_external_file_link_fails(self):
        self.windows()
        external = self.file('outside/token.json').resolve()
        link = Path('source/apps/muyon/build/windows/x64/runner/Release/token.json')
        link.symlink_to(external)
        with self.assertRaisesRegex(RuntimeError, 'Windows.*link'):
            self.run_package('windows')
        self.assertFalse(any(Path('packages').glob('*.zip')))

    def test_windows_external_directory_link_fails(self):
        self.windows()
        self.file('outside/token.json')
        link = Path('source/apps/muyon/build/windows/x64/runner/Release/extra')
        link.symlink_to(Path('outside').resolve(), target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'Windows.*link'):
            self.run_package('windows')
        self.assertFalse(any(Path('packages').glob('*.zip')))

    def test_windows_internal_link_policy_fails(self):
        self.windows()
        link = Path('source/apps/muyon/build/windows/x64/runner/Release/extra.dll')
        link.symlink_to('flutter_windows.dll')
        with self.assertRaisesRegex(RuntimeError, 'Windows.*link'):
            self.run_package('windows')

    def test_windows_reparse_point_fails(self):
        self.windows()
        root = Path('source/apps/muyon/build/windows/x64/runner/Release')
        original = Path.lstat

        def reparse_lstat(path):
            result = original(path)
            if path == root:
                return SimpleNamespace(st_mode=result.st_mode, st_file_attributes=0x400)
            return result

        # Linux fixture for Windows junction/reparse metadata, not a real junction.
        with patch.object(Path, 'lstat', reparse_lstat):
            with self.assertRaisesRegex(RuntimeError, 'Windows.*reparse'):
                self.run_package('windows')

    def test_windows_resolve_outside_release_fails(self):
        self.windows()
        root = Path('source/apps/muyon/build/windows/x64/runner/Release')
        original = Path.resolve
        external = self.file('outside/token.json').resolve()

        def resolve_outside(path, *args, **kwargs):
            if path == root / 'muyon.exe':
                return external
            return original(path, *args, **kwargs)

        with patch.object(Path, 'resolve', resolve_outside):
            with self.assertRaisesRegex(RuntimeError, 'outside Release'):
                self.run_package('windows')

    def test_forbidden_output_paths(self):
        for path in ['.env', 'folder/debug.keystore', 'keys', 'rawlogs', 'test.log', 'key.properties']:
            with self.subTest(path=path), self.assertRaises(RuntimeError):
                package.check_paths([path])


if __name__ == '__main__':
    unittest.main()
