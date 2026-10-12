#!/usr/bin/env python3
"""Local keyless Android experience packaging.

Release APK only. No dart-define secrets, no SDK/NDK auto-download, no new
credentials. Artifact name includes the full build SHA; SHA256 and manifest
are written next to the APK.

Intended for internal validation. The app release build currently signs with
the Android debug key (see apps/muyon/android/app/build.gradle.kts).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

SECRET_DEFINE_RE = re.compile(
    r'(?i)(api[_-]?key|secret|token|password|passwd|credential|private[_-]?key|auth)'
)
SHA_RE = re.compile(r'^[0-9a-f]{40}$')


def fail(message: str) -> None:
    raise SystemExit(message)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def check_paths(paths) -> None:
    """Reject credential / log / traversal paths inside APK entries."""
    for path in paths:
        normalized = str(path).replace('\\', '/')
        if not (
            normalized
            and not normalized.startswith('/')
            and ':' not in normalized
            and not any(ord(ch) < 32 or ord(ch) == 127 for ch in normalized)
        ):
            raise RuntimeError('Unsafe absolute or malformed path in build output')
        parts = normalized.split('/')
        if '..' in parts:
            raise RuntimeError('Directory traversal in build output')
        names = [part.lower() for part in parts if part not in {'', '.'}]
        if not names:
            raise RuntimeError('Empty normalized path in build output')
        for name in names:
            if (
                name.startswith('.env')
                or name in {'rawlogs', 'keys', 'key.properties'}
                or name.endswith(('.log', '.keystore', '.jks', '.p12', '.pfx', '.pem', '.key'))
            ):
                raise RuntimeError('Credential or raw-log path in build output')


def resolve_android_home() -> Path | None:
    for key in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        value = os.environ.get(key)
        if value:
            path = Path(value).expanduser()
            if path.is_dir():
                return path.resolve()
    candidate = Path.home() / 'Android' / 'Sdk'
    if candidate.is_dir():
        return candidate.resolve()
    return None


def require_sdk(home: Path, require_ndk: bool) -> dict:
    """Verify cached SDK layout. Never fetches missing components."""
    info: dict = {'home': str(home)}
    require(home.is_dir(), f'Android SDK missing at {home}')
    platforms = home / 'platforms'
    build_tools = home / 'build-tools'
    platform_tools = home / 'platform-tools'
    require(
        platforms.is_dir() and any(platforms.iterdir()),
        'Android SDK platforms/ missing (will not auto-fetch)',
    )
    require(
        build_tools.is_dir() and any(build_tools.iterdir()),
        'Android SDK build-tools/ missing (will not auto-fetch)',
    )
    require(platform_tools.is_dir(), 'Android SDK platform-tools/ missing (will not auto-fetch)')
    signers = list(build_tools.glob('*/apksigner')) + list(build_tools.glob('*/apksigner.bat'))
    require(signers, 'Android apksigner missing under build-tools (will not auto-fetch)')
    signer = max(signers, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.parent.name)))
    info['build_tools'] = signer.parent.name
    info['apksigner'] = str(signer)
    ndk_root = home / 'ndk'
    ndk_dirs = [p for p in ndk_root.iterdir()] if ndk_root.is_dir() else []
    if require_ndk:
        require(ndk_dirs, 'Android NDK missing under SDK ndk/ (will not auto-fetch)')
    info['ndk'] = sorted(p.name for p in ndk_dirs)
    return info


def git_output(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ['git', '-C', str(repo), *args],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    require(completed.returncode == 0, f'git {" ".join(args)} failed: {completed.stderr.strip()}')
    return completed.stdout.strip()


def resolve_build_sha(repo: Path, override: str | None) -> str:
    sha = override or git_output(repo, 'rev-parse', 'HEAD')
    require(bool(SHA_RE.fullmatch(sha)), 'Full lowercase 40-character build SHA required')
    return sha


def refuse_dart_defines(extra_args: list[str]) -> None:
    """Keyless experience packages must not embed dart-define values."""
    i = 0
    while i < len(extra_args):
        arg = extra_args[i]
        if arg == '--dart-define-from-file' or arg.startswith('--dart-define-from-file='):
            fail('keyless Android packaging forbids --dart-define-from-file (可能嵌入密钥)')
        if arg == '--dart-define' or arg.startswith('--dart-define='):
            value = (
                arg.split('=', 1)[1]
                if arg.startswith('--dart-define=')
                else (extra_args[i + 1] if i + 1 < len(extra_args) else '')
            )
            if SECRET_DEFINE_RE.search(value):
                fail(f'keyless packaging rejects secret-like dart-define: {value.split("=", 1)[0]}')
            fail('keyless Android packaging forbids all --dart-define flags')
        i += 1


def run_checked(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    completed = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    require(
        completed.returncode == 0,
        f'command failed ({completed.returncode}): {" ".join(args)}\n{completed.stdout}',
    )
    return completed


def sha256_file(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()


def verify_debug_signing(apksigner: Path, apk: Path) -> dict:
    completed = run_checked([str(apksigner), 'verify', '--print-certs', str(apk)])
    require('CN=Android Debug' in completed.stdout, 'Expected internal debug-signed APK')
    match = re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', completed.stdout)
    require(bool(match), 'Certificate digest missing')
    return {
        'method': 'android-debug-key',
        'certificate_sha256': match.group(1),
        'distribution': False,
    }


def read_java_version() -> str:
    if not shutil.which('java'):
        return ''
    completed = subprocess.run(
        ['java', '-version'],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    lines = completed.stdout.strip().splitlines()
    return lines[0] if lines else ''


def package_apk(
    *,
    repo: Path,
    output: Path,
    flutter: str,
    build_sha: str,
    sdk_info: dict,
    skip_pub_get: bool,
    extra_args: list[str],
) -> dict:
    refuse_dart_defines(extra_args)
    app = repo / 'apps' / 'muyon'
    require((app / 'android').is_dir(), f'Android project missing under {app}')
    require(shutil.which(flutter) or Path(flutter).exists(), f'Flutter SDK binary not found: {flutter}')

    if not skip_pub_get:
        run_checked([flutter, 'pub', 'get', '--enforce-lockfile'], cwd=repo)

    # Release must not use --no-pub: otherwise stale GeneratedPluginRegistrant can
    # keep integration_test and break compile (see apps/muyon/README.md).
    build_cmd = [flutter, 'build', 'apk', '--release', *extra_args]
    run_checked(build_cmd, cwd=app)

    source = app / 'build' / 'app' / 'outputs' / 'flutter-apk' / 'app-release.apk'
    require(source.is_file() and source.stat().st_size > 0, f'Release APK missing: {source}')

    with zipfile.ZipFile(source) as archive:
        try:
            check_paths(archive.namelist())
        except RuntimeError as exc:
            fail(f'APK contains sensitive path: {exc}')

    signing = verify_debug_signing(Path(sdk_info['apksigner']), source)

    output.mkdir(parents=True, exist_ok=True)
    artifact_name = f'muyon-android-{build_sha}-internal.apk'
    artifact = output / artifact_name
    shutil.copyfile(source, artifact)
    digest = sha256_file(artifact)
    (output / f'{artifact_name}.sha256').write_text(f'{digest}  {artifact_name}\n', encoding='utf-8')

    flutter_version: dict | str
    try:
        raw = run_checked([flutter, '--version', '--machine']).stdout
        flutter_version = json.loads(raw)
    except Exception:
        flutter_version = 'unavailable'

    manifest = {
        'build_sha': build_sha,
        'platform': 'android',
        'os': platform.platform(),
        'architecture': platform.machine(),
        'tools': {
            'flutter': flutter_version,
            'python': platform.python_version(),
            'java': read_java_version(),
            'android_build_tools': sdk_info.get('build_tools'),
            'android_ndk': sdk_info.get('ndk', []),
        },
        'signing': signing,
        'dart_defines': [],
        'build_command': build_cmd,
        'internal_validation_only': True,
        'keyless': True,
        'sdk_home': sdk_info.get('home'),
        'files': [{'path': artifact_name, 'bytes': artifact.stat().st_size, 'sha256': digest}],
    }
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Keyless Android experience packaging')
    parser.add_argument('--repo', type=Path, default=None, help='Repository root (default: auto-detect)')
    parser.add_argument('--output', type=Path, required=True, help='Output directory for APK + manifest')
    parser.add_argument('--flutter', default='flutter', help='Flutter binary')
    parser.add_argument('--build-sha', default=None, help='Override build SHA (full lowercase 40-char)')
    parser.add_argument('--skip-pub-get', action='store_true', help='Skip flutter pub get --enforce-lockfile')
    parser.add_argument(
        '--allow-missing-ndk',
        action='store_true',
        help='Do not require NDK directory (still never auto-fetches)',
    )
    parser.add_argument(
        '--require-ndk',
        action='store_true',
        help='Require cached NDK (default behavior; kept for explicit test/CLI use)',
    )
    parser.add_argument('extra', nargs=argparse.REMAINDER, help='After -- : extra flutter args (dart-define forbidden)')
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv[1:] if argv is not None else None)
    extra = list(args.extra)
    if extra and extra[0] == '--':
        extra = extra[1:]

    repo = args.repo
    if repo is None:
        repo = Path(__file__).resolve().parents[2]
    repo = repo.resolve()
    require((repo / 'apps' / 'muyon').is_dir(), f'Not a Muyon repo root: {repo}')

    home = resolve_android_home()
    require(
        home is not None,
        'Android SDK not found. Set ANDROID_HOME to an already-cached SDK; will not auto-fetch.',
    )
    # Default: require NDK. --allow-missing-ndk opts out. --require-ndk keeps default explicit.
    need_ndk = not args.allow_missing_ndk
    sdk_info = require_sdk(home, require_ndk=need_ndk)

    if not shutil.which('java') and not os.environ.get('JAVA_HOME'):
        fail('Java 17+ required for Android release build, but java was not found (will not install)')

    build_sha = resolve_build_sha(repo, args.build_sha)
    package_apk(
        repo=repo,
        output=args.output.resolve(),
        flutter=args.flutter,
        build_sha=build_sha,
        sdk_info=sdk_info,
        skip_pub_get=args.skip_pub_get,
        extra_args=extra,
    )
    print(f'Packaged keyless Android APK for {build_sha} -> {args.output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
