"""Required compiled Linux evidence; a recognized RED still exits nonzero."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import urllib.request

from ffi_evidence import classify
from full_evidence import rust_full, jvm_full, panic_full

ROOT = Path(__file__).resolve().parents[4]
CORE = ROOT / 'experiments/redesign/android-rust-bridge-lab/core'
KOTLIN_URL = 'https://github.com/JetBrains/kotlin/releases/download/v2.2.20/kotlin-compiler-2.2.20.zip'
KOTLIN_SHA = '81f0264c9073b5cbbdb3ff8418cf2c5dac076879fc156fa1a6462f5a5acc4420'
JNA_URL = 'https://repo.maven.apache.org/maven2/net/java/dev/jna/jna/5.19.1/jna-5.19.1.jar'
JNA_SHA = '4fb141dd8ef6b0585ffceea4bc49602fbc6312fa977e2c488794ea3e6aafecae'
INTEGRATION = {
    'bundled_contract_reaches_rust_catalog',
    'all_variants_preserve_fixture_counts_identity_and_fresh_generation',
    'protocol_rejection_has_valid_sibling',
    'request_id_accepts_only_frozen_safe_ascii_bound',
    'handshake_declares_only_metadata_surface',
    'errors_are_closed_safe_unit_variants',
}
UNIT = {
    'inspection_rejects_missing_malformed_or_overflowed_counts',
    'declaration_rejection_is_closed_and_has_valid_sibling',
    'panic_boundary_contains_failure_and_remains_usable',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory():
    for path, names in [(CORE / 'tests/bridge_contract.rs', INTEGRATION), (CORE / 'src/lib.rs', UNIT)]:
        actual = re.findall(r'#\[test\]\s*fn\s+(\w+)\s*\(', path.read_text())
        if len(actual) != len(names) or set(actual) != names:
            raise RuntimeError('fixed_test_inventory_changed')


def tracked_inputs():
    paths = subprocess.check_output(['git', 'ls-files', '-z',
        'experiments/redesign/core-agent-lab', 'experiments/redesign/plugin-contract-lab',
        'experiments/redesign/android-rust-bridge-lab',
        '.github/workflows/android-rust-bridge.yml'], cwd=ROOT).decode().split('\0')
    return {name: sha(ROOT / name) for name in paths if name}


def run(command, log, env, cwd=CORE, timeout=600, required=True):
    with log.open('wb') as output:
        child = subprocess.Popen([str(x) for x in command], cwd=cwd, env=env,
                                 stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        timed_out = False
        forced = False
        try:
            status = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            status = 124
        finally:
            try:
                os.killpg(child.pid, 0)
            except ProcessLookupError:
                pass
            else:
                forced = True
                os.killpg(child.pid, signal.SIGKILL)
            child.wait(timeout=10)
    record = dict(command=[str(x) for x in command], cwd=str(cwd), exit_code=status,
                  timed_out=timed_out, forced_owned_group_cleanup=forced,
                  raw_sha256=sha(log))
    log.with_suffix(log.suffix + '.json').write_text(json.dumps(record, indent=2) + '\n')
    print(f'{log.name}: exit={status} timeout={timed_out} forced_cleanup={forced}', flush=True)
    if timed_out or forced or (required and status != 0):
        print(log.read_text(errors='replace')[-6000:], flush=True)
        raise RuntimeError('command_invalid_or_failed')
    return status


def download(url, output, expected):
    with urllib.request.urlopen(url, timeout=60) as source, output.open('wb') as target:
        shutil.copyfileobj(source, target)
    if sha(output) != expected:
        raise RuntimeError('official_tool_hash_mismatch')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['rust-red', 'jvm-red', 'full'], required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    args = parser.parse_args()
    evidence, work = args.evidence_dir.resolve(), args.work_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    original = tracked_inputs()
    (evidence / 'source-inputs-before.json').write_text(json.dumps(original, indent=2) + '\n')
    result = dict(classification='INVALID', accepted=False, mode=args.mode, android_runtime='NOT_RUN')
    try:
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        if not re.fullmatch('[0-9a-f]{40}', source):
            raise RuntimeError('source_identity')
        if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip():
            raise RuntimeError('unclean_source')
        inventory()
        env = dict(os.environ, MUYON_BRIDGE_BUILD_ID=source, CARGO_TERM_COLOR='never',
                   CARGO_INCREMENTAL='0', CARGO_TARGET_DIR=str(work / 'shipping-target'))
        run(['rustc', '--version'], evidence / 'rustc.log', env)
        run(['cargo', '--version'], evidence / 'cargo.log', env)
        if not (evidence / 'rustc.log').read_text().startswith('rustc 1.99.0 '):
            raise RuntimeError('pinned_rust_toolchain_missing')
        run(['cargo', 'fetch', '--locked'], evidence / 'locked-fetch.log', env)
        run(['cargo', 'test', '--offline', '--locked', '--release', '--no-run'], evidence / 'compile.log', env)
        run(['cargo', 'build', '--offline', '--locked', '--release', '--lib'], evidence / 'shipping-build.log', env)
        shipping = evidence / 'shipping/libmuyon_android_contract_bridge.so'
        shipping.parent.mkdir()
        shutil.copyfile(work / 'shipping-target/release/libmuyon_android_contract_bridge.so', shipping)
        shipping_sha = sha(shipping)
        result.update(source_sha=source, library_sha256=shipping_sha, cargo_lock_sha256=sha(CORE / 'Cargo.lock'),
                      shipping_features=[], test_inventory_source='631e148f4ea467639d0ed9c0244ed1e821348900',
                      integration_names=sorted(INTEGRATION), unit_names=sorted(UNIT))
        if args.mode == 'full':
            run(['cargo', 'test', '--offline', '--locked', '--release', '--no-fail-fast'],
                evidence / 'rust-full.log', env)
            if not rust_full((evidence / 'rust-full.log').read_text(), UNIT, INTEGRATION):
                raise RuntimeError('rust_full_names_or_counts')
        if args.mode == 'rust-red':
            behavior = evidence / 'behavior.log'
            status = run(['cargo', 'test', '--offline', '--locked', '--release', '--test',
                'bridge_contract', 'bundled_contract_reaches_rust_catalog', '--', '--exact', '--nocapture'],
                behavior, env, required=False)
        else:
            tools = work / 'tools'; tools.mkdir()
            download(KOTLIN_URL, tools / 'kotlin.zip', KOTLIN_SHA)
            download(JNA_URL, tools / 'jna.jar', JNA_SHA)
            run(['unzip', '-q', tools / 'kotlin.zip', '-d', tools], evidence / 'kotlin-extract.log', env)
            run(['java', '-version'], evidence / 'java.log', env)
            if not re.search(r'version "17\.', (evidence / 'java.log').read_text()):
                raise RuntimeError('pinned_jdk17_missing')
            cli_env = dict(env, CARGO_TARGET_DIR=str(work / 'bindgen-target'))
            run(['cargo', 'build', '--offline', '--locked', '--release', '--features', 'bindings',
                 '--bin', 'uniffi-bindgen'], evidence / 'bindgen-build.log', cli_env)
            bindgen = work / 'bindgen-target/release/uniffi-bindgen'
            result.update(bindgen_sha256=sha(bindgen), kotlin_zip_sha256=sha(tools / 'kotlin.zip'), jna_jar_sha256=sha(tools / 'jna.jar'))
            for profile in ['android', 'jvm']:
                run([bindgen, 'generate', shipping, '--crate', 'muyon_android_contract_bridge',
                    '--language', 'kotlin', '--config', CORE / f'uniffi.{profile}.toml', '--no-format',
                    '--out-dir', evidence / profile], evidence / f'generate-{profile}.log', cli_env)
            binding = evidence / 'jvm/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
            result.update(jvm_binding_sha256=sha(binding), android_binding_sha256=sha(evidence / 'android/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'))
            run(['bash', tools / 'kotlinc/bin/kotlinc', binding, Path(__file__).with_name('BridgeProbe.kt'),
                 '-jvm-target', '17', '-classpath', tools / 'jna.jar', '-include-runtime', '-d', work / 'probe.jar'],
                evidence / 'kotlin-compile.log', env)
            if 'ffiTestPanicProbe' in binding.read_text():
                raise RuntimeError('probe_export_in_shipping_binding')
            result['probe_jar_sha256'] = sha(work / 'probe.jar')
            behavior = evidence / 'behavior.log'
            status = run(['java', '-cp', str(work / 'probe.jar') + ':' + str(tools / 'jna.jar'),
                         'muyon.bridgechecks.BridgeProbe', 'full' if args.mode == 'full' else 'jvm-red', source, shipping], behavior, env,
                         timeout=30, required=False)
            if args.mode == 'full':
                if status != 0 or not jvm_full(behavior.read_text(), source, shipping_sha):
                    raise RuntimeError('jvm_full_names_or_identity')
                run(['java', '-cp', str(work / 'probe.jar') + ':' + str(tools / 'jna.jar'),
                     'muyon.bridgechecks.BridgeProbe', 'load-negative', source, work / 'absent.so'],
                    evidence / 'load-negative.log', env, timeout=30)
                if (evidence / 'load-negative.log').read_text() != 'ANDROID_BRIDGE_JVM_PASS missing_native_load_stays_unavailable\n':
                    raise RuntimeError('load_negative_not_observed')
                committed = ROOT / 'experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
                generated = evidence / 'android/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
                if committed.read_bytes() != generated.read_bytes():
                    raise RuntimeError('android_generated_binding_byte_mismatch')
                probe_env = dict(env, CARGO_TARGET_DIR=str(work / 'panic-target'))
                run(['cargo', 'build', '--offline', '--locked', '--release', '--lib', '--features', 'ffi-test-probes'],
                    evidence / 'panic-build.log', probe_env)
                panic_lib = evidence / 'panic/libmuyon_android_contract_bridge.so'
                panic_lib.parent.mkdir()
                shutil.copyfile(work / 'panic-target/release/libmuyon_android_contract_bridge.so', panic_lib)
                panic_sha = sha(panic_lib)
                run([bindgen, 'generate', panic_lib, '--crate', 'muyon_android_contract_bridge', '--language', 'kotlin',
                     '--config', CORE / 'uniffi.jvm.toml', '--no-format', '--out-dir', evidence / 'panic/jvm'],
                    evidence / 'generate-panic.log', cli_env)
                panic_binding = evidence / 'panic/jvm/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
                if 'ffiTestPanicProbe' not in panic_binding.read_text():
                    raise RuntimeError('panic_export_missing')
                run(['bash', tools / 'kotlinc/bin/kotlinc', panic_binding, Path(__file__).with_name('BridgeProbe.kt'),
                     Path(__file__).with_name('PanicProbe.kt'), '-jvm-target', '17', '-classpath', tools / 'jna.jar',
                     '-include-runtime', '-d', work / 'panic.jar'], evidence / 'panic-compile.log', env)
                run(['java', '-cp', str(work / 'panic.jar') + ':' + str(tools / 'jna.jar'),
                     'muyon.bridgechecks.PanicProbe', source, panic_lib], evidence / 'panic.log', env, timeout=30)
                if not panic_full((evidence / 'panic.log').read_text(), source, panic_sha) or sha(panic_lib) != panic_sha:
                    raise RuntimeError('panic_recovery_not_observed')
                result.update(panic_library_sha256=panic_sha, panic_features=['ffi-test-probes'],
                              panic_binding_sha256=sha(panic_binding), panic_jar_sha256=sha(work / 'panic.jar'))
        if sha(shipping) != shipping_sha:
            raise RuntimeError('shipping_library_changed')
        if args.mode == 'full':
            result.update(accepted=True, classification='GREEN', rust_unit_passed=3, rust_integration_passed=6,
                          rust_doc_passed=0, jvm_shipping_passed=5, load_negative_passed=1, panic_recovery_passed=1)
        else:
            result.update(classify(args.mode, behavior.read_text(errors='replace'), status, source, shipping_sha))
        result['raw_sha256'] = sha(behavior)
        print(behavior.read_text(errors='replace')[-6000:], flush=True)
        return status if result['accepted'] else 1
    except Exception as failure:
        result.update(classification='INVALID', accepted=False, failure=type(failure).__name__ + ':' + str(failure))
        print('ANDROID_BRIDGE_INVALID ' + result['failure'], flush=True)
        return 1
    finally:
        current = tracked_inputs()
        result['source_inputs_unchanged'] = original == current
        (evidence / 'source-inputs-after.json').write_text(json.dumps(current, indent=2) + '\n')
        if original != current:
            result.update(classification='INVALID', accepted=False, failure='source_inputs_changed')
        (evidence / 'verdict.json').write_text(json.dumps(result, indent=2) + '\n')
        if not result['source_inputs_unchanged']:
            raise RuntimeError('source_inputs_changed')


if __name__ == '__main__':
    raise SystemExit(main())
