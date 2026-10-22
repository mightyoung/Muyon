"""macOS-only exact-source API26 packaging inputs. This is NOT the CI producer.

No device execution, model traffic, dependency download, credential access or old
HTTP runner. Prerequisites (Rust targets, locked Cargo dependencies, official JNA
AAR) must already exist. Every build records the actual compiler, never CI's pin.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import zipfile

from elf_check import inspect
from verify_inputs import ABIS, BINDING, CONFIG, check_aar, digest, verify

ROOT = Path(__file__).resolve().parents[4]
CORE = ROOT / 'experiments/redesign/android-rust-bridge-lab/core'
TARGET_DIR = Path('/private/tmp/muyon-live-android-target')
NDK_VERSION = '28.2.13676358'
AAR_SHA = 'b57125cb7d16253f0d65a80f7d3a4c3664effa711b8bdbb7f87fb572ce1624ed'
JNI_SHA = {
    'arm64-v8a': 'abc26e994517bcaa3309acdb0a27373864086c7569c89d3087b8626fada9ef06',
    'x86_64': '3809247e9b804a05ed8377b87d545cf5b5e97f960f75e725bc8497b40260e417',
}
TARGETS = {'arm64-v8a': 'aarch64-linux-android', 'x86_64': 'x86_64-linux-android'}


def output(command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def source_inputs():
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    return {name: digest(ROOT / name) for name in names if name and (ROOT / name).is_file()}


def clean_exact_source(expected):
    if re.fullmatch('[0-9a-f]{40}', expected) is None or output(['git', 'rev-parse', 'HEAD']) != expected:
        raise RuntimeError('exact_source_sha_required')
    if output(['git', 'status', '--porcelain', '--untracked-files=all']):
        raise RuntimeError('clean_source_required')


def run(command, log, env):
    with log.open('w') as destination:
        result = subprocess.run([str(arg) for arg in command], cwd=CORE, env=env,
                                stdin=subprocess.DEVNULL, stdout=destination,
                                stderr=subprocess.STDOUT, timeout=1800, check=False)
    if result.returncode:
        raise RuntimeError('command_failed:' + log.name)


def symbols(raw):
    rows = []
    for line in raw.splitlines():
        match = re.fullmatch(r'\s*\d+:\s+\S+\s+\d+\s+\S+\s+(GLOBAL|WEAK|LOCAL)\s+\S+\s+(\S+)\s+(\S+)(?:\s+\(\d+\))?\s*', line)
        if match:
            rows.append(match.groups())
    if not rows:
        raise RuntimeError('unparsed_dynamic_symbols')
    return rows


def imports(library, info, triple, tools, evidence, env, prefix):
    exports, stubs = set(), {}
    for name in info['needed']:
        stub = tools / 'sysroot/usr/lib' / triple / '26' / name
        if not stub.is_file():
            raise RuntimeError('api26_stub_missing')
        log = evidence / f'{prefix}-stub-{name}.log'
        run([tools / 'bin/llvm-readelf', '--dyn-syms', '--wide', stub], log, env)
        exports.update(name.split('@')[0] for binding, ndx, name in symbols(log.read_text())
                       if ndx != 'UND' and binding in ('GLOBAL', 'WEAK'))
        stubs[name] = digest(stub)
    log = evidence / f'{prefix}-dynsym.log'
    run([tools / 'bin/llvm-readelf', '--dyn-syms', '--wide', library], log, env)
    required = {name.split('@')[0] for binding, ndx, name in symbols(log.read_text())
                if ndx == 'UND' and binding == 'GLOBAL'}
    if required - exports:
        raise RuntimeError('unresolved_api26_strong_imports')
    return dict(api26_stub_hashes=stubs, strong_imports=sorted(required), missing=[], Android_runtime='NOT_RUN')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-source-sha', required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--jna-aar', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, default=Path.home() / 'Library/Android/sdk')
    args = parser.parse_args()
    evidence = args.evidence_dir.resolve()
    if evidence.is_relative_to(ROOT) or evidence.exists():
        raise RuntimeError('new_external_evidence_directory_required')
    evidence.mkdir(parents=True)
    result = dict(classification='LOCAL_FAILED', CI_producer='NOT_RUN', CI_rust_1_99='NOT_RUN',
                  Android_runtime='NOT_RUN', model_requests=0, target_directory=str(TARGET_DIR))
    before = None
    try:
        clean_exact_source(args.expected_source_sha)
        if platform.system() != 'Darwin':
            raise RuntimeError('macos_host_required')
        before = source_inputs()
        compiler = output(['rustc', '--version'])
        result.update(rustc=compiler, host=platform.platform(), source_sha=args.expected_source_sha)
        aar = args.jna_aar.resolve()
        check_aar(aar, dict(aar_sha256=AAR_SHA, jni_sha256=JNI_SHA))
        ndk = args.sdk.resolve() / 'ndk' / NDK_VERSION
        if not re.search(r'^Pkg.Revision\s*=\s*28\.2\.13676358\s*$', (ndk / 'source.properties').read_text(), re.M):
            raise RuntimeError('ndk_revision')
        tools = ndk / 'toolchains/llvm/prebuilt/darwin-x86_64'
        if not (tools / 'bin/llvm-readelf').is_file():
            raise RuntimeError('macos_ndk_tools_missing')
        installed = set(output(['rustup', 'target', 'list', '--installed']).splitlines())
        if not set(TARGETS.values()) <= installed:
            raise RuntimeError('android_rust_targets_missing')
        env = dict(os.environ, MUYON_BRIDGE_BUILD_ID=args.expected_source_sha,
                   CARGO_INCREMENTAL='0', CARGO_TARGET_DIR=str(TARGET_DIR), CARGO_TERM_COLOR='never')
        # Native generator uses macOS SQLite. Android below uses bundled target C.
        native = dict(env, RUSTFLAGS='-l sqlite3')
        run(['cargo', 'build', '--offline', '--locked', '--lib', '--bin', 'uniffi-bindgen', '--features', 'bindings'],
            evidence / 'native-generator-build.log', native)
        generated = evidence / 'generated'
        run([TARGET_DIR / 'debug/uniffi-bindgen', 'generate', TARGET_DIR / 'debug/libmuyon_android_contract_bridge.dylib',
             '--language', 'kotlin', '--no-format', '--config', CORE / 'uniffi.android.toml', '--out-dir', generated],
            evidence / 'generated-bindings.log', native)
        binding = ROOT / BINDING
        regenerated = generated / 'com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
        if regenerated.read_bytes() != binding.read_bytes():
            raise RuntimeError('genuine_generated_binding_mismatch')
        text = regenerated.read_text()
        for symbol in ['fun `withHost`', 'fun `withRegisteredTools`', 'fun `snapshot`',
                       'fun `exchangeLiveChat`', 'fun `settleChat`', 'fun `chatSettlement`',
                       'class ServiceOwnerRunControl', 'fun `allowed`']:
            if symbol not in text:
                raise RuntimeError('required_generated_api_missing')
        input_root = evidence / 'bridge-inputs'; input_root.mkdir()
        manifest = dict(format_version=2, source_sha=args.expected_source_sha, build_identity=args.expected_source_sha,
                        protocol=1, namespace='muyon_android_contract_bridge', min_api=26,
                        android_binding_sha256=digest(binding), android_config_sha256=digest(ROOT / CONFIG),
                        rust_libraries={}, jna=dict(version='5.19.1', aar_sha256=AAR_SHA, jni_sha256=JNI_SHA))
        result['abis'] = {}
        for abi in ABIS:
            clean_exact_source(args.expected_source_sha)
            triple = TARGETS[abi]; linker = tools / 'bin' / (triple + '26-clang')
            target_env = dict(env, RUSTFLAGS='-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384')
            target_env['CARGO_TARGET_' + triple.upper().replace('-', '_') + '_LINKER'] = str(linker)
            target_env['CC_' + triple.replace('-', '_')] = str(linker)
            target_env['AR_' + triple.replace('-', '_')] = str(tools / 'bin/llvm-ar')
            logs = evidence / abi; logs.mkdir()
            run([linker, '--version'], logs / 'clang.log', target_env)
            run(['cargo', 'build', '--offline', '--locked', '--release', '--lib', '--no-default-features', '--target', triple],
                logs / 'link.log', target_env)
            relative = f'jniLibs/{abi}/libmuyon_android_contract_bridge.so'
            library = input_root / relative; library.parent.mkdir(parents=True)
            shutil.copyfile(TARGET_DIR / triple / 'release/libmuyon_android_contract_bridge.so', library)
            info = inspect(library.read_bytes(), abi)
            info['api26_import_compatibility'] = imports(library, info, triple, tools, logs, target_env, 'rust')
            jni = logs / 'libjnidispatch.so'
            with zipfile.ZipFile(aar) as archive:
                jni.write_bytes(archive.read(f'jni/{abi}/libjnidispatch.so'))
            jna = inspect(jni.read_bytes(), abi, rust=False)
            jna['api26_import_compatibility'] = imports(jni, jna, triple, tools, logs, target_env, 'jna')
            manifest['rust_libraries'][abi] = dict(path=relative, sha256=digest(library))
            result['abis'][abi] = dict(rust_target=triple, rust_elf=info, jna_elf=jna,
                                      clang_sha256=digest(linker.resolve()))
        (input_root / 'bridge-inputs.json').write_text(json.dumps(manifest, indent=2) + '\n')
        verify(input_root, args.expected_source_sha, binding.resolve(), (ROOT / CONFIG).resolve(), aar)
        clean_exact_source(args.expected_source_sha)
        if source_inputs() != before:
            raise RuntimeError('source_inputs_changed')
        result.update(classification='LOCAL_LINK_VERIFIED', source_inputs_unchanged=True,
                      ndk_version=NDK_VERSION, ndk_properties_sha256=digest(ndk / 'source.properties'),
                      generated_binding_bytecmp=True, packaging_inputs_verified=True,
                      bridge_inputs=str(input_root), jna_aar=str(aar),
                      limitation='Local compiler/build/ELF/packaging checks only; CI producer and Android runtime NOT_RUN')
        return 0
    except Exception as error:
        result['failure'] = str(error)
        return 1
    finally:
        if before is not None:
            result['source_inputs_unchanged'] = source_inputs() == before
        (evidence / 'local-build-report.json').write_text(json.dumps(result, indent=2) + '\n')
        print('LOCAL_ANDROID_BUILD ' + json.dumps({k: v for k, v in result.items() if k != 'abis'}, sort_keys=True))


if __name__ == '__main__':
    raise SystemExit(main())
