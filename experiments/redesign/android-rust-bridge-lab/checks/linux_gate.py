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
import time
import urllib.request

from ffi_evidence import SERVICE_MODES, classify
from host_checkpoint import inventory as checkpoint_inventory, target_green as checkpoint_target_green, oracle_inventory, oracle_red, temp_red
from full_evidence import rust_full, jvm_full, panic_full
from mapper_control import inventory as mapper_inventory, classify as classify_mapper_control
from binding_source import PINS as BINDING_SOURCE_PINS, emit as emit_android_binding

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


def service_inventory(root=ROOT, descriptor=None):
    """Freeze a separately named service target from author test source, not output."""
    try:
        contract = json.loads((descriptor or Path(__file__).with_name('service_cases.json')).read_text())
        manifests = {'experiments/redesign/rust-agent-host-lab/core/Cargo.toml',
                     'experiments/redesign/android-rust-bridge-lab/core/Cargo.toml'}
        if (not isinstance(contract, dict) or type(contract.get('version')) is not int
                or contract['version'] != 1 or contract['manifest'] not in manifests):
            raise ValueError('shape')
        red = contract['red']; names = contract['test_names']
        if (not isinstance(red, dict) or not isinstance(names, list) or not names
                or not all(isinstance(name, str) and re.fullmatch(r'[A-Za-z_]\w*', name) for name in names)
                or len(set(names)) != len(names) or red['test'] not in names
                or not isinstance(red['target'], str) or not re.fullmatch(r'[A-Za-z_]\w*', red['target'])
                or type(red['filtered']) is not int or red['filtered'] != len(names) - 1
                or contract['test_file'] != str(Path(contract['manifest']).parent / 'tests' / (red['target'] + '.rs'))):
            raise ValueError('target')
        for key, size in [('fixed_contract_commit', 40), ('author_test_commit', 40),
                          ('test_blob_sha', 40), ('test_sha256', 64)]:
            if not isinstance(contract[key], str) or not re.fullmatch('[0-9a-f]{' + str(size) + '}', contract[key]):
                raise ValueError('provenance')
        body = (root / contract['test_file']).read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(body)).encode() + b'\0' + body).hexdigest()
        actual = re.findall(r'#\[test\]\s*fn\s+(\w+)\s*\(', body.decode('utf-8'))
        if (hashlib.sha256(body).hexdigest() != contract['test_sha256'] or blob != contract['test_blob_sha']
                or len(actual) != len(names) or set(actual) != set(names)):
            raise ValueError('test source')
        return contract
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as failure:
        raise RuntimeError('fixed_service_inventory_invalid') from failure


def tracked_inputs():
    paths = subprocess.check_output(['git', 'ls-files', '-z',
        'experiments/redesign/core-agent-lab', 'experiments/redesign/plugin-contract-lab',
        'experiments/redesign/rust-agent-host-lab',
        'experiments/redesign/android-rust-bridge-lab', 'experiments/redesign/android-compose-lab',
        '.github/workflows/android-rust-bridge.yml', '.github/workflows/android-min26.yml',
        'docs/design/ANDROID-RUST-BRIDGE-INPUTS-V2.md',
        'docs/design/ANDROID-RUST-BRIDGE-INPUTS-V2.schema.json'], cwd=ROOT).decode().split('\0')
    return {name: sha(ROOT / name) for name in paths if name}


def run(command, log, env, cwd=CORE, timeout=600, required=True):
    with log.open('wb') as output:
        child = subprocess.Popen([str(x) for x in command], cwd=cwd, env=env,
                                 stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        timed_out = False
        forced = False
        try:
            status = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            status = 124
        finally:
            child.wait(timeout=0) if child.poll() is not None else None
            def live_group():
                live = []
                for stat in Path('/proc').glob('[0-9]*/stat'):
                    try:
                        fields = stat.read_text().rsplit(')', 1)[1].split()
                        if int(fields[2]) == child.pid and fields[0] != 'Z':
                            live.append(int(stat.parent.name))
                    except (OSError, ValueError, IndexError):
                        continue
                return live
            # A no-daemon Gradle worker may still be shutting down when its
            # launcher exits. Give owned group members a bounded natural exit.
            deadline = time.monotonic() + (0 if timed_out else 3)
            while live_group() and time.monotonic() < deadline:
                time.sleep(0.05)
            live_before_cleanup = live_group()
            if live_before_cleanup:
                forced = True
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            child.wait(timeout=10)
            deadline = time.monotonic() + 3
            while live_group() and time.monotonic() < deadline:
                time.sleep(0.05)
            live_after_cleanup = live_group()
    record = dict(command=[str(x) for x in command], cwd=str(cwd), exit_code=status,
                  timed_out=timed_out, forced_owned_group_cleanup=forced,
                  live_before_cleanup=live_before_cleanup, live_after_cleanup=live_after_cleanup,
                  raw_sha256=sha(log))
    log.with_suffix(log.suffix + '.json').write_text(json.dumps(record, indent=2) + '\n')
    print(f'{log.name}: exit={status} timeout={timed_out} forced_cleanup={forced}', flush=True)
    if timed_out or forced or live_after_cleanup or (required and status != 0):
        print(log.read_text(errors='replace')[-6000:], flush=True)
        raise RuntimeError('command_invalid_or_failed')
    return status


def download(url, output, expected):
    with urllib.request.urlopen(url, timeout=60) as source, output.open('wb') as target:
        shutil.copyfileobj(source, target)
    if sha(output) != expected:
        raise RuntimeError('official_tool_hash_mismatch')


def host_checkpoint(evidence, work, source, oracle=False, green=False, temp=False):
    if sum([green, oracle, temp]) > 1:
        raise RuntimeError('invalid_host_mode')
    contract = checkpoint_inventory(ROOT, temp=True) if temp else checkpoint_inventory(ROOT, service=True) if green else checkpoint_inventory(ROOT)
    oracle_contract = oracle_inventory(ROOT) if oracle else None
    host = ROOT / contract['manifest']
    env = dict(os.environ, CARGO_TERM_COLOR='never', CARGO_INCREMENTAL='0',
               CARGO_TARGET_DIR=str(work / 'host-target'))
    run(['rustc', '--version'], evidence / 'rustc.log', env)
    run(['cargo', '--version'], evidence / 'cargo.log', env)
    if not (evidence / 'rustc.log').read_text().startswith('rustc 1.99.0 '):
        raise RuntimeError('pinned_rust_toolchain_missing')
    run(['cargo', 'fetch', '--locked'], evidence / 'host-fetch.log', env, cwd=host.parent)
    run(['cargo', 'test', '--offline', '--locked', '--release', '--no-run'],
        evidence / 'host-compile.log', env, cwd=host.parent)
    plugin = ROOT / 'experiments/redesign/plugin-contract-lab/core'
    run(['cargo', 'build', '--offline', '--locked', '--release', '--bin', 'muyon-plugin-contract-lab'],
        evidence / 'plugin-build.log', env, cwd=plugin)
    binary = work / 'host-target/release/muyon-plugin-contract-lab'
    if not binary.is_file():
        raise RuntimeError('actual_plugin_binary_missing')
    env['MUYON_PLUGIN_CONTRACT_BIN'] = str(binary)
    results = []
    for target in contract['targets']:
        if temp and target == 'service_lifecycle':
            continue
        raw = evidence / (target + '.log')
        status = run(['cargo', 'test', '--offline', '--locked', '--release', '--test', target],
                     raw, env, cwd=host.parent, required=False)
        row = checkpoint_target_green(target, raw.read_text(errors='replace'), status, service=True) if green or temp else checkpoint_target_green(target, raw.read_text(errors='replace'), status)
        row.update(raw_sha256=sha(raw), source=contract['targets'][target])
        results.append(row)
        print(raw.read_text(errors='replace'), flush=True)
        print('SERVICE_HOST_CHECKPOINT_TARGET ' + json.dumps(row, sort_keys=True), flush=True)
    result = dict(accepted=all(row['accepted'] for row in results),
        classification=('SERVICE_HOST_GREEN' if green else 'HOST_CHECKPOINT_GREEN') if all(row['accepted'] for row in results) else 'INVALID',
        source_sha=source, plugin_binary_sha256=sha(binary), shipping_or_service_green=False,
        host_cargo_lock_sha256=sha(host.parent / 'Cargo.lock'),
        descriptor_sha256=sha(Path(__file__).with_name('service_temp_red_cases.json' if temp else 'service_host_green_cases.json' if green else 'host_checkpoint_cases.json')),
        author_test_commit=contract['author_commit'], targets=results,
        executed_tests=sum(row['observed_tests'] for row in results),
        not_run={'service_controller': 'initial refusal; not executed by this partial checkpoint',
                 'service_jvm': 'NOT_RUN', 'service_inverses': 'NOT_RUN',
                 'unit_doc_tests': 'NOT_RUN; whole host test executables compiled only',
                 'legacy_and_native_inverses': 'NOT_RUN by partial checkpoint; mandatory final gates unchanged',
                 'android_runtime': 'NOT_RUN'})
    if green:
        result['rust_service_host_green'] = result['accepted']
        result['not_run'].pop('service_controller')
        result['scope'] = 'source-fixed Rust Service controller/worker/oracle groups only; JVM and Android runtime separate'
    if temp:
        result['not_run'].pop('service_controller')
        result['not_run']['temp_evidence_byte_preservation_tail'] = 'NOT_RUN'
        result['temp_red'] = dict(accepted=False, classification='NOT_RUN', reason='component_gate_failed')
        if result['accepted']:
            target = contract['red']['target']; raw = evidence / 'service-temp-red.log'
            status = run(['cargo', 'test', '--offline', '--locked', '--release', '--test', target,
                          '--', '--nocapture'], raw, env, cwd=host.parent, required=False)
            verdict = temp_red(raw.read_text(errors='replace'), status)
            result.update(accepted=verdict['accepted'], classification=verdict['classification'],
                          command_exit_code=status, temp_red=dict(verdict, raw_sha256=sha(raw)))
            result['executed_tests'] += verdict['observed_tests']
            print(raw.read_text(errors='replace'), flush=True)
            print('SERVICE_TEMP_RED_VERDICT ' + json.dumps(result['temp_red'], sort_keys=True), flush=True)
    if oracle_contract:
        result['oracle_test_source'] = oracle_contract
        result['oracle'] = dict(accepted=False, classification='NOT_RUN', reason='component_gate_failed')
        if result['accepted']:
            red = oracle_contract['red']; raw = evidence / 'service-oracle-red.log'
            status = run(['cargo', 'test', '--offline', '--locked', '--release', '--test',
                red['target'], red['test'], '--', '--exact', '--nocapture'],
                raw, env, cwd=host.parent, required=False)
            verdict = oracle_red(raw.read_text(errors='replace'), status, source, sha(binary))
            result.update(accepted=verdict['accepted'], classification=verdict['classification'],
                          command_exit_code=status, oracle=dict(verdict, raw_sha256=sha(raw)))
            print(raw.read_text(errors='replace'), flush=True)
            print('SERVICE_CONTROLLER_ORACLE_VERDICT ' + json.dumps(result['oracle'], sort_keys=True), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=['rust-red', 'jvm-red', 'full', 'service-host-checkpoint', 'service-oracle-red', 'service-host-green', 'mapper-control-red', 'service-temp-red'] + SERVICE_MODES, required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    parser.add_argument('--emit-android-source', action='store_true')
    args = parser.parse_args()
    if args.emit_android_source and args.mode != 'service-jvm-red':
        parser.error('android source emission requires service-jvm-red')
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
        if args.mode in ['service-host-checkpoint', 'service-oracle-red', 'service-host-green', 'service-temp-red']:
            result.update(host_checkpoint(evidence, work, source, oracle=args.mode == 'service-oracle-red',
                                          green=args.mode == 'service-host-green', temp=args.mode == 'service-temp-red'))
            return result.get('command_exit_code', 0) if result['accepted'] else 1
        inventory()
        mapper = mapper_inventory(ROOT) if args.mode == 'mapper-control-red' else None
        service = service_inventory() if args.mode in SERVICE_MODES else None
        env = dict(os.environ, MUYON_BRIDGE_BUILD_ID=source, CARGO_TERM_COLOR='never',
                   CARGO_INCREMENTAL='0', CARGO_TARGET_DIR=str(work / 'shipping-target'))
        run(['rustc', '--version'], evidence / 'rustc.log', env)
        run(['cargo', '--version'], evidence / 'cargo.log', env)
        if not (evidence / 'rustc.log').read_text().startswith('rustc 1.99.0 '):
            raise RuntimeError('pinned_rust_toolchain_missing')
        run(['cargo', 'fetch', '--locked'], evidence / 'locked-fetch.log', env)
        run(['cargo', 'test', '--offline', '--locked', '--release', '--no-run'], evidence / 'compile.log', env)
        if service:
            run(['cargo', 'test', '--offline', '--locked', '--release', '--no-run',
                 '--manifest-path', ROOT / service['manifest']], evidence / 'service-compile.log', env)
        run(['cargo', 'build', '--offline', '--locked', '--release', '--lib'], evidence / 'shipping-build.log', env)
        shipping = evidence / 'shipping/libmuyon_android_contract_bridge.so'
        shipping.parent.mkdir()
        shutil.copyfile(work / 'shipping-target/release/libmuyon_android_contract_bridge.so', shipping)
        shipping_sha = sha(shipping)
        result.update(source_sha=source, library_sha256=shipping_sha, cargo_lock_sha256=sha(CORE / 'Cargo.lock'),
                      shipping_features=[], test_inventory_source='631e148f4ea467639d0ed9c0244ed1e821348900',
                      integration_names=sorted(INTEGRATION), unit_names=sorted(UNIT))
        if mapper:
            result.update(mapper_test_inventory=mapper,
                          mapper_contract_sha256=sha(Path(__file__).with_name('mapper_control_cases.json')))
        if service:
            result.update(service_test_inventory_source=service['author_test_commit'],
                          service_test_names=service['test_names'], service_target=service['red']['target'],
                          service_test_sha256=service['test_sha256'],
                          service_contract_sha256=sha(Path(__file__).with_name('service_cases.json')),
                          service_reach_scope='correlated controller entry/refusal; Agent dispatch not claimed')
        if args.mode == 'full':
            run(['cargo', 'test', '--offline', '--locked', '--release', '--no-fail-fast'],
                evidence / 'rust-full.log', env)
            if not rust_full((evidence / 'rust-full.log').read_text(), UNIT, INTEGRATION):
                raise RuntimeError('rust_full_names_or_counts')
            print((evidence / 'rust-full.log').read_text(), flush=True)
        if args.mode == 'service-rust-red':
            behavior = evidence / 'behavior.log'
            status = run(['cargo', 'test', '--offline', '--locked', '--release',
                '--manifest-path', ROOT / service['manifest'], '--test', service['red']['target'],
                service['red']['test'], '--', '--exact', '--nocapture'], behavior, env, required=False)
        elif args.mode == 'rust-red':
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
            result.update(android_config_sha256=sha(CORE / 'uniffi.android.toml'), jvm_config_sha256=sha(CORE / 'uniffi.jvm.toml'), jvm_binding_sha256=sha(binding), android_binding_sha256=sha(evidence / 'android/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'))
            if args.emit_android_source:
                emit_android_binding(evidence, {key: result[key] for key in BINDING_SOURCE_PINS})
                result['android_binding_source_emitted'] = True
            probe_sources = [Path(__file__).with_name('BridgeProbe.kt')]
            if service:
                probe_sources.append(Path(__file__).with_name('ServiceProbe.kt'))
            if mapper:
                probe_sources.append(Path(__file__).with_name('MapperProbe.kt'))
                probe_sources.extend(ROOT / path for path in mapper['sources'])
            run(['bash', tools / 'kotlinc/bin/kotlinc', binding, *probe_sources,
                 '-jvm-target', '17', '-classpath', tools / 'jna.jar', '-include-runtime', '-d', work / 'probe.jar'],
                evidence / 'kotlin-compile.log', env)
            if 'ffiTestPanicProbe' in binding.read_text():
                raise RuntimeError('probe_export_in_shipping_binding')
            result['probe_jar_sha256'] = sha(work / 'probe.jar')
            behavior = evidence / 'behavior.log'
            probe_class = 'muyon.bridgechecks.MapperProbe' if mapper else 'muyon.bridgechecks.ServiceProbe' if service else 'muyon.bridgechecks.BridgeProbe'
            probe_mode = args.mode if service else 'full' if args.mode == 'full' else 'jvm-red'
            probe_args = [source, shipping] if mapper else [probe_mode, source, shipping] + ([work] if service else [])
            status = run(['java', '-cp', str(work / 'probe.jar') + ':' + str(tools / 'jna.jar'),
                         probe_class, *probe_args], behavior, env,
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
                print((evidence / 'load-negative.log').read_text(), flush=True)
                print((evidence / 'panic.log').read_text(), flush=True)
                result.update(panic_library_sha256=panic_sha, panic_features=['ffi-test-probes'],
                              panic_binding_sha256=sha(panic_binding), panic_jar_sha256=sha(work / 'panic.jar'))
        if sha(shipping) != shipping_sha:
            raise RuntimeError('shipping_library_changed')
        if args.mode == 'full':
            result.update(accepted=True, classification='GREEN', rust_unit_passed=3, rust_integration_passed=6,
                          rust_doc_passed=0, jvm_shipping_passed=5, load_negative_passed=1, panic_recovery_passed=1)
        elif mapper:
            result.update(classify_mapper_control(behavior.read_text(errors='replace'), status, source, shipping_sha))
        else:
            result.update(classify(args.mode, behavior.read_text(errors='replace'), status, source, shipping_sha,
                                   service=service['red'] if service else None))
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
        print('ANDROID_BRIDGE_LINUX_VERDICT ' + json.dumps(result, sort_keys=True), flush=True)
        if not result['source_inputs_unchanged']:
            raise RuntimeError('source_inputs_changed')


if __name__ == '__main__':
    raise SystemExit(main())
