"""Package only native build output; never repository, caches, credentials or logs."""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import zipfile


def command(*args):
    executable = shutil.which(args[0]) or args[0]
    return subprocess.check_output((executable, *args[1:]), text=True, stderr=subprocess.STDOUT).strip()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def check_paths(paths):
    for path in paths:
        name = Path(path).name.lower()
        require(
            not (name.startswith('.env') or name in {'rawlogs', 'keys', 'key.properties'}
                 or name.endswith(('.log', '.keystore', '.jks', '.p12', '.pfx', '.pem', '.key'))),
            'Credential or raw-log path in build output',
        )


def main():
    target = os.environ['TARGET_SHA']
    workflow = os.environ['WORKFLOW_SHA']
    selected = os.environ['PACKAGE_PLATFORM']
    require(re.fullmatch('[0-9a-f]{40}', target), 'Invalid source SHA')
    require(command('git', '-C', 'source', 'rev-parse', 'HEAD') == target, 'Source HEAD mismatch')
    require(command('git', '-C', 'workflow', 'rev-parse', 'HEAD') == workflow, 'Workflow HEAD mismatch')
    output = Path('packages')
    output.mkdir(exist_ok=False)
    app = Path('source/apps/muyon')
    stem = f'muyon-{selected}-{target}'
    tools = {
        'flutter': json.loads(command('flutter', '--version', '--machine')),
        'dart': command('dart', '--version'),
        'python': platform.python_version(),
    }

    if selected == 'android':
        source = app / 'build/app/outputs/flutter-apk/app-release.apk'
        require(source.is_file(), 'Release APK missing')
        sdk = Path(os.environ['ANDROID_HOME'])
        candidates = list((sdk / 'build-tools').glob('*/apksigner'))
        require(candidates, 'Android apksigner missing')
        signer = max(candidates, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.parent.name)))
        certificate = command(str(signer), 'verify', '--print-certs', str(source))
        require('CN=Android Debug' in certificate, 'Expected internal debug-signed APK')
        digest = re.search(r'Signer #1 certificate SHA-256 digest: (\w+)', certificate)
        require(digest, 'Certificate digest missing')
        signing = {'method': 'android-debug-key', 'certificate_sha256': digest[1], 'distribution': False}
        tools['java'] = command('java', '-version')
        tools['android_build_tools'] = signer.parent.name
        gradle = command(str((app / 'android/gradlew').resolve()), '--version')
        tools['gradle'] = next(line for line in gradle.splitlines() if line.startswith('Gradle '))
        with zipfile.ZipFile(source) as archive:
            check_paths(archive.namelist())
        package = output / f'{stem}-internal.apk'
        shutil.copyfile(source, package)
    elif selected == 'macos':
        bundles = list((app / 'build/macos/Build/Products/Release').glob('*.app'))
        require(len(bundles) == 1, 'Expected exactly one complete .app')
        source = bundles[0]
        require((source / 'Contents/MacOS/muyon').is_file(), 'macOS executable missing')
        require((source / 'Contents/Frameworks/FlutterMacOS.framework').is_dir(), 'Flutter framework missing')
        check_paths(p.relative_to(source) for p in source.rglob('*'))
        command('codesign', '--verify', '--deep', '--strict', str(source))
        signature = command('codesign', '-dv', '--verbose=4', str(source))
        require('Signature=adhoc' in signature, 'Only project ad-hoc signing allowed')
        signing = {'method': 'ad-hoc', 'developer_id': False, 'notarized': False}
        tools['xcode'] = command('xcodebuild', '-version')
        tools['swift'] = command('swift', '--version')
        package = output / f'{stem}.app.zip'
        # ditto preserves bundle symlinks, permissions and the .app enclosing folder.
        command('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(source), str(package))
    elif selected == 'windows':
        source = app / 'build/windows/x64/runner/Release'
        require(all((source / name).exists() for name in
                    ['muyon.exe', 'flutter_windows.dll', 'data/icu.dat', 'data/app.so', 'data/flutter_assets']),
                'Complete Windows Release bundle missing')
        check_paths(p.relative_to(source) for p in source.rglob('*'))
        signature = command('powershell', '-NoProfile', '-Command',
                            f"(Get-AuthenticodeSignature -LiteralPath '{source}/muyon.exe').Status")
        require(signature == 'NotSigned', 'Expected unsigned Windows executable')
        signing = {'method': 'unsigned', 'authenticode': False}
        tools['cmake'] = command('cmake', '--version').splitlines()[0]
        vswhere = Path(os.environ['ProgramFiles(x86)']) / 'Microsoft Visual Studio/Installer/vswhere.exe'
        tools['visual_studio'] = json.loads(command(str(vswhere), '-latest', '-products', '*',
                                                   '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
                                                   '-format', 'json'))[0]['installationVersion']
        package = output / f'{stem}-Release.zip'
        with zipfile.ZipFile(package, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(source.rglob('*')):
                if path.is_file():
                    archive.write(path, Path('Release') / path.relative_to(source))
    else:
        raise RuntimeError('Unsupported platform')

    require(package.is_file() and package.stat().st_size > 0, 'Empty package')
    with package.open('rb') as stream:
        hasher = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
        digest = hasher.hexdigest()
    manifest = {
        'source_sha': target,
        'workflow_sha': workflow,
        'workflow_ref': os.environ['WORKFLOW_REF'],
        'run_id': os.environ['GITHUB_RUN_ID'],
        'run_attempt': os.environ['GITHUB_RUN_ATTEMPT'],
        'platform': selected,
        'os': platform.platform(),
        'architecture': platform.machine(),
        'runner_arch': os.environ['RUNNER_ARCH'],
        'tools': tools,
        'signing': signing,
        'internal_validation_only': True,
        'files': [{'path': package.name, 'bytes': package.stat().st_size, 'sha256': digest}],
    }
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
