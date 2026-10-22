"""Build one exact-source Compose/native APK from the two real ABI producer outputs.

Uses existing V2 verifier and APK inspection. No legacy host suite, provider, HTTP,
credential, user database or manual release-artifact workflow is invoked.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'experiments/redesign/android-rust-bridge-lab/checks'))
from package_gate import (AAR_SHA, AAR_URL, BINDING, CONFIG, GRADLE_SHA, GRADLE_URL,
                          apk_entries, apk_sdk_and_abi)
from linux_gate import download, run, sha
from verify_inputs import ABIS, verify
from android_gate import JNI_SHA, ensure_sdk


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--artifacts', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    evidence, work = args.evidence.resolve(), args.work.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip()
    # Verify generated source from the same Linux metadata build, not a copied old binding.
    assert (args.artifacts / 'scoped/generated-binding.kt').read_bytes() == (ROOT / BINDING).read_bytes()
    inputs = evidence / 'bridge-inputs'
    inputs.mkdir()
    manifest = dict(format_version=2, source_sha=source, build_identity=source, protocol=1,
                    namespace='muyon_android_contract_bridge', min_api=26,
                    android_binding_sha256=sha(ROOT / BINDING),
                    android_config_sha256=sha(ROOT / CONFIG), rust_libraries={},
                    jna=dict(version='5.19.1', aar_sha256=AAR_SHA, jni_sha256=JNI_SHA))
    for abi in ABIS:
        producer = args.artifacts / abi
        result = json.loads((producer / 'manifest.json').read_text())
        library = producer / 'libmuyon_android_contract_bridge.so'
        assert result['classification'] == 'GREEN' and result['source_inputs_unchanged'] is True
        assert result['source_sha'] == result['build_identity'] == source
        assert result['abi'] == abi and result['min_api'] == 26
        assert result['library_sha256'] == sha(library)
        relative = f'jniLibs/{abi}/{library.name}'
        destination = inputs / relative
        destination.parent.mkdir(parents=True)
        shutil.copyfile(library, destination)
        manifest['rust_libraries'][abi] = dict(path=relative, sha256=sha(destination))
    (inputs / 'bridge-inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
    env = dict(os.environ, GRADLE_USER_HOME=str(work / 'gradle-cache'),
               ANDROID_USER_HOME=str(work / 'android-user'))
    sdk = ensure_sdk(evidence, env, ['platforms;android-36', 'build-tools;35.0.0'])
    aar = work / 'jna.aar'
    download(AAR_URL, aar, AAR_SHA)
    verify(inputs, source, ROOT / BINDING, ROOT / CONFIG, aar)
    download(GRADLE_URL, work / 'gradle.zip', GRADLE_SHA)
    run(['unzip', '-q', work / 'gradle.zip', '-d', work], evidence / 'gradle-extract.log', env)
    gradle = work / 'gradle-8.13/bin/gradle'
    ui = ROOT / 'experiments/redesign/android-compose-lab'
    run([gradle, '--no-daemon', '--stacktrace', '--console=plain', '-p', ui,
         '-PmuyonBridgeInputs=' + str(inputs), '-PmuyonBridgeSourceSha=' + source,
         ':state:check', ':app:assembleDebug', ':app:assembleDebugAndroidTest', ':app:lintDebug'],
        evidence / 'combined-build.log', env, cwd=ui, timeout=1800)
    app = ui / 'app/build/outputs/apk/debug/app-debug.apk'
    tests = ui / 'app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
    entries = apk_entries(app, manifest)
    run([sdk / 'build-tools/35.0.0/aapt2', 'dump', 'badging', app], evidence / 'apk-badging.log', env)
    assert apk_sdk_and_abi((evidence / 'apk-badging.log').read_text())
    for name, path in [('app-debug.apk', app), ('app-debug-androidTest.apk', tests)]:
        run([sdk / 'build-tools/35.0.0/zipalign', '-c', '-P', '16', '4', path], evidence / (name + '-alignment.log'), env)
        shutil.copyfile(path, evidence / name)
    (evidence / 'package-result.json').write_text(json.dumps(dict(
        source_sha=source, min_api=26, native_entries=entries, apk_sha256=sha(app),
        test_apk_sha256=sha(tests), build='PASS', Android_runtime='NOT_RUN',
        business_source='synthetic schema12', model_api_called=False), indent=2) + '\n')
    print('COMBINED_NATIVE_COMPOSE_PACKAGE_PASS source=' + source, flush=True)


if __name__ == '__main__':
    main()
