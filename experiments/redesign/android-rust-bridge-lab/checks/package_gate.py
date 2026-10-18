"""Aggregate exact-source ABI inputs, invoke shared validator and inspect actual APK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile

from android_gate import AAR_SHA, AAR_URL, JNI_SHA, NDK, ensure_sdk
from linux_gate import CORE, ROOT, download, run, sha, tracked_inputs
from verify_inputs import ABIS, BINDING, CONFIG, decode, verify

GRADLE_URL = 'https://services.gradle.org/distributions/gradle-8.13-bin.zip'
GRADLE_SHA = '20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78'
UI = ROOT / 'experiments/redesign/android-compose-lab'
# Existing ComposeBOM2025.09.01 -> ui-graphics-android1.9.2 -> graphics-path1.0.1.
# Pins are official published AAR bytes, independently frozen before APK diagnosis.
GRAPHICS_AAR_SHA = '8ca4032b6d79b351f0b59ad4b580eddbb9423e1652f7c958830687f1eee2ec03'
GRAPHICS_JNI_SHA = {
    'arm64-v8a': '41e9a793c43a0f4fddb19e33f346bace464f30f888ba7b9eaf96294ea115bfb6',
    'x86_64': '4e56c996f13670e70082658de7880c4020eabf4f25e43387f88ed78a713fc9f0',
}

MARKERS = ['16/16 pure JVM state checks passed', '22/22 local UI state checks passed',
           '29/29 diagnostic coordinator checks passed; native FFI/Android runtime NOT_RUN']


def aggregate(artifacts, target, source):
    if {item.name for item in artifacts.iterdir()} != {'linux', *ABIS}:
        raise RuntimeError('exact_producer_abi_set')
    linux = decode((artifacts / 'linux/verdict.json').read_bytes())
    if not (linux['accepted'] is True and linux['classification'] == 'GREEN'
            and linux['source_sha'] == source and linux['shipping_features'] == []
            and linux['source_inputs_unchanged'] is True):
        raise RuntimeError('linux_provenance')
    binding = artifacts / 'linux/android/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
    if binding.read_bytes() != (ROOT / BINDING).read_bytes():
        raise RuntimeError('generated_android_binding_mismatch')
    value = dict(format_version=2, source_sha=source, build_identity=source, protocol=1,
                 namespace='muyon_android_contract_bridge', min_api=26,
                 android_binding_sha256=sha(ROOT / BINDING), android_config_sha256=sha(ROOT / CONFIG),
                 rust_libraries={}, jna=dict(version='5.19.1', aar_sha256=AAR_SHA, jni_sha256=JNI_SHA))
    target.mkdir()
    for abi in ABIS:
        directory = artifacts / abi
        manifest = decode((directory / 'manifest.json').read_bytes())
        library = directory / 'libmuyon_android_contract_bridge.so'
        exact = dict(classification='GREEN', source_sha=source, build_identity=source, abi=abi,
                     protocol=1, namespace='muyon_android_contract_bridge', min_api=26,
                     shipping_features=[], ndk_version=NDK, source_inputs_unchanged=True,
                     cargo_lock_sha256=sha(CORE / 'Cargo.lock'), android_config_sha256=sha(ROOT / CONFIG),
                     jna_aar_sha256=AAR_SHA, jna_jni_sha256=JNI_SHA[abi], library_sha256=sha(library))
        if any(type(manifest.get(key)) is not type(expected) or manifest.get(key) != expected for key, expected in exact.items()):
            raise RuntimeError('abi_provenance:' + abi)
        relative = f'jniLibs/{abi}/libmuyon_android_contract_bridge.so'
        destination = target / relative; destination.parent.mkdir(parents=True)
        shutil.copyfile(library, destination)
        value['rust_libraries'][abi] = dict(path=relative, sha256=sha(destination))
    (target / 'bridge-inputs.json').write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')
    return value


def check_graphics_aar(path):
    if path.is_symlink() or not path.is_file() or sha(path) != GRAPHICS_AAR_SHA:
        raise RuntimeError('resolved_graphics_aar_hash')
    with zipfile.ZipFile(path) as archive:
        for abi, digest in GRAPHICS_JNI_SHA.items():
            name = f'jni/{abi}/libandroidx.graphics.path.so'
            if archive.namelist().count(name) != 1 or hashlib.sha256(archive.read(name)).hexdigest() != digest:
                raise RuntimeError('resolved_graphics_jni_hash')


def apk_entries(apk, inputs):
    expected = {f'lib/{abi}/libmuyon_android_contract_bridge.so': inputs['rust_libraries'][abi]['sha256'] for abi in ABIS}
    expected.update({f'lib/{abi}/libjnidispatch.so': JNI_SHA[abi] for abi in ABIS})
    expected.update({f'lib/{abi}/libandroidx.graphics.path.so': GRAPHICS_JNI_SHA[abi] for abi in ABIS})
    with zipfile.ZipFile(apk) as archive, apk.open('rb') as raw:
        # Inspect every member before selecting lib/*.so; no extraction occurs.
        names = []
        for member in archive.infolist():
            name = member.orig_filename
            components = (name[:-1] if name.endswith('/') else name).split('/')
            if (name != member.filename or name.startswith('/') or '\\' in name
                    or '\x00' in name or re.match(r'^[A-Za-z]:', name)
                    or any(part in ['', '.', '..'] for part in components)):
                raise RuntimeError('apk_member_path')
            names.append(name)
        if len(names) != len(set(names)):
            raise RuntimeError('apk_duplicate_member')
        native = [entry.filename for entry in archive.infolist() if entry.filename.startswith('lib/') and entry.filename.endswith('.so')]
        if len(native) != len(expected) or set(native) != set(expected):
            print('ANDROID_BRIDGE_APK_NATIVE_INVENTORY ' + json.dumps(dict(
                apk_sha256=sha(apk), count=len(native), expected=sorted(expected),
                observed=[name[:160] for name in native[:50]], bounded=True)), flush=True)
            raise RuntimeError('apk_exact_native_entries')
        for name, digest in expected.items():
            info = archive.getinfo(name)
            actual_digest = hashlib.sha256(archive.read(name)).hexdigest()
            if info.compress_type != zipfile.ZIP_STORED or actual_digest != digest:
                print('ANDROID_BRIDGE_APK_NATIVE_MISMATCH ' + json.dumps(dict(
                    path=name, expected_sha256=digest, actual_sha256=actual_digest,
                    compression=info.compress_type)), flush=True)
                raise RuntimeError('apk_native_hash_or_compression:' + name)
            raw.seek(info.header_offset)
            header = raw.read(30)
            if header[:4] != b'PK\x03\x04':
                raise RuntimeError('apk_local_header')
            name_size, extra_size = struct.unpack_from('<HH', header, 26)
            if (info.header_offset + 30 + name_size + extra_size) % 16384 != 0:
                raise RuntimeError('apk_native_zip_alignment')
    return expected


def apk_sdk_and_abi(badging):
    # Pinned build-tools35 emits minSdkVersion (not legacy sdkVersion).
    return (re.findall(r'^minSdkVersion:(.*)$', badging, re.M) == ["'26'"]
            and re.findall(r'^targetSdkVersion:(.*)$', badging, re.M) == ["'36'"]
            and re.findall(r'^native-code:(.*)$', badging, re.M) == [" 'arm64-v8a' 'x86_64'"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    args = parser.parse_args()
    evidence, work = args.evidence_dir.resolve(), args.work_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True); work.mkdir(parents=True, exist_ok=True)
    before = tracked_inputs()
    result = dict(classification='INVALID', Android_runtime='NOT_RUN')
    try:
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        env = dict(os.environ, GRADLE_USER_HOME=str(work / 'gradle-cache'), ANDROID_USER_HOME=str(work / 'android-user'))
        if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip():
            raise RuntimeError('unclean_source')
        sdk = ensure_sdk(evidence, env, ['platforms;android-36', 'build-tools;35.0.0'])
        tools = sdk / 'build-tools/35.0.0'
        inputs = aggregate(args.artifacts.resolve(), evidence / 'bridge-inputs', source)
        aar = work / 'jna.aar'; download(AAR_URL, aar, AAR_SHA)
        verify(evidence / 'bridge-inputs', source, ROOT / BINDING, ROOT / CONFIG, aar)
        download(GRADLE_URL, work / 'gradle.zip', GRADLE_SHA)
        run(['unzip', '-q', work / 'gradle.zip', '-d', work], evidence / 'gradle-extract.log', env)
        gradle = work / 'gradle-8.13/bin/gradle'
        run([gradle, '--version'], evidence / 'gradle-version.log', env)
        command = [gradle, '--no-daemon', '--stacktrace', '--console=plain', '-p', UI,
                   '-PmuyonBridgeInputs=' + str(evidence / 'bridge-inputs'), '-PmuyonBridgeSourceSha=' + source,
                   ':state:check', ':app:lintDebug', ':app:assembleDebug', ':app:assembleDebugAndroidTest']
        run(command, evidence / 'required-gradle.log', env, cwd=UI, timeout=1200)
        raw = (evidence / 'required-gradle.log').read_text()
        for marker in MARKERS:
            if raw.count(marker) != 1:
                raise RuntimeError('required_state_marker:' + marker)
        print('\n'.join(line for line in raw.splitlines() if re.match(r'^(PASS|FAIL) ', line)), flush=True)
        print('\n'.join(marker for marker in MARKERS), flush=True)
        # Recheck against the actually resolved Gradle AAR, not only a second download.
        resolved = list((work / 'gradle-cache/caches/modules-2/files-2.1/net.java.dev.jna/jna/5.19.1').glob('*/jna-5.19.1.aar'))
        if len(resolved) != 1:
            raise RuntimeError('resolved_jna_aar_inventory')
        verify(evidence / 'bridge-inputs', source, ROOT / BINDING, ROOT / CONFIG, resolved[0])
        graphics = list((work / 'gradle-cache/caches/modules-2/files-2.1/androidx.graphics/graphics-path/1.0.1').glob('*/graphics-path-1.0.1.aar'))
        if len(graphics) != 1:
            raise RuntimeError('resolved_graphics_aar_inventory')
        check_graphics_aar(graphics[0])
        result.update(resolved_graphics_aar_sha256=sha(graphics[0]), graphics_path_version='1.0.1')
        result.update(source_sha=source, protocol=1, min_api=26,
                      bridge_inputs_sha256=sha(evidence / 'bridge-inputs/bridge-inputs.json'),
                      resolved_jna_aar_sha256=sha(resolved[0]), state_passed=16,
                      local_ui_passed=22, diagnostic_passed=29, gradle_required_exit=0)
        apk = UI / 'app/build/outputs/apk/debug/app-debug.apk'
        test_apk = UI / 'app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
        if not apk.is_file() or not test_apk.is_file():
            raise RuntimeError('required_apk_missing')
        entries = apk_entries(apk, inputs)
        run([tools / 'zipalign', '-c', '-P', '16', '4', apk], evidence / 'zipalign-app.log', env)
        run([tools / 'zipalign', '-c', '-P', '16', '4', test_apk], evidence / 'zipalign-test.log', env)
        run([tools / 'aapt2', 'dump', 'badging', apk], evidence / 'apk-badging.log', env)
        badging = (evidence / 'apk-badging.log').read_text()
        result.update(apk_sha256=sha(apk), test_apk_sha256=sha(test_apk),
                      apk_native_entries=entries, zipalign_app=True, zipalign_test=True, lint=True)
        badging_rows = [line[:512] for line in badging.splitlines()
                       if any(field in line for field in ['sdkVersion', 'SdkVersion', 'native-code'])][:8]
        print('ANDROID_BRIDGE_AAPT_BADGING ' + json.dumps(dict(
            rows=badging_rows, raw_sha256=sha(evidence / 'apk-badging.log'), bounded=True)), flush=True)
        if not apk_sdk_and_abi(badging):
            raise RuntimeError('apk_sdk_or_abi')
        for name, path in [('app-debug.apk', apk), ('app-debug-androidTest.apk', test_apk)]:
            shutil.copyfile(path, evidence / name)
        result.update(classification='GREEN', source_sha=source, protocol=1, min_api=26,
            state_passed=16, local_ui_passed=22, diagnostic_passed=29,
            generated_binding_sha256=sha(ROOT / BINDING), android_config_sha256=sha(ROOT / CONFIG),
            bridge_inputs_sha256=sha(evidence / 'bridge-inputs/bridge-inputs.json'),
            gradle_zip_sha256=sha(work / 'gradle.zip'), resolved_jna_aar_sha256=sha(resolved[0]),
            apk_sha256=sha(apk), test_apk_sha256=sha(test_apk), apk_native_entries=entries,
            zipalign_app=True, zipalign_test=True, lint=True)

        print((evidence / 'zipalign-app.log').read_text(), flush=True)
        print((evidence / 'apk-badging.log').read_text()[-4000:], flush=True)
        return 0
    except Exception as failure:
        result['failure'] = type(failure).__name__ + ':' + str(failure)
        return 1
    finally:
        result['source_inputs_unchanged'] = before == tracked_inputs()
        if not result['source_inputs_unchanged']:
            result.update(classification='INVALID', failure='source_inputs_changed')
        (evidence / 'source-inputs.json').write_text(json.dumps(before, indent=2) + '\n')
        (evidence / 'verdict.json').write_text(json.dumps(result, indent=2) + '\n')
        print('ANDROID_BRIDGE_PACKAGE_VERDICT ' + json.dumps(result, sort_keys=True), flush=True)
        if not result['source_inputs_unchanged']:
            raise RuntimeError('source_inputs_changed')


if __name__ == '__main__':
    raise SystemExit(main())
