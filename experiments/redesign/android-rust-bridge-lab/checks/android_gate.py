"""Fresh API26 link/ELF producer; no Android runtime is exercised."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

from elf_check import inspect
from linux_gate import CORE, ROOT, download, run, sha, tracked_inputs
from verify_inputs import check_aar

NDK = '28.2.13676358'
AAR_URL = 'https://repo.maven.apache.org/maven2/net/java/dev/jna/jna/5.19.1/jna-5.19.1.aar'
AAR_SHA = 'b57125cb7d16253f0d65a80f7d3a4c3664effa711b8bdbb7f87fb572ce1624ed'
JNI_SHA = {'arm64-v8a': 'abc26e994517bcaa3309acdb0a27373864086c7569c89d3087b8626fada9ef06',
           'x86_64': '3809247e9b804a05ed8377b87d545cf5b5e97f960f75e725bc8497b40260e417'}
TARGETS = {'arm64-v8a': ('aarch64-linux-android', 'aarch64-linux-android'),
           'x86_64': ('x86_64-linux-android', 'x86_64-linux-android')}


def symbols(raw):
    rows = []
    for line in raw.splitlines():
        match = re.fullmatch(r'\s*\d+:\s+\S+\s+\d+\s+\S+\s+(GLOBAL|WEAK|LOCAL)\s+\S+\s+(\S+)\s+(\S+)(?:\s+\(\d+\))?\s*', line)
        if match:
            rows.append(match.groups())
    if not rows:
        raise RuntimeError('unparsed_dynamic_symbols')
    return rows


def api26_imports(library, info, triple, ndk, readelf, evidence, env, prefix):
    exports = set()
    stubs = {}
    for name in info['needed']:
        stub = ndk / 'toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib' / triple / '26' / name
        if not stub.is_file():
            raise RuntimeError('api26_stub_missing')
        log = evidence / f'{prefix}-stub-{name}.log'
        run([readelf, '--dyn-syms', '--wide', stub], log, env)
        exports.update(name.split('@')[0] for binding, ndx, name in symbols(log.read_text()) if ndx != 'UND' and binding in ['GLOBAL', 'WEAK'])
        stubs[name] = sha(stub)
    log = evidence / f'{prefix}-dynsym.log'
    run([readelf, '--dyn-syms', '--wide', library], log, env)
    required = {name.split('@')[0] for binding, ndx, name in symbols(log.read_text()) if ndx == 'UND' and binding == 'GLOBAL'}
    missing = sorted(required - exports)
    if missing:
        raise RuntimeError('unresolved_api26_strong_imports:' + ','.join(missing))
    return dict(api26_stub_hashes=stubs, strong_imports=sorted(required), missing=[],
                evidence='named strong imports resolve against exact API26 NDK stubs; Android runtime NOT_RUN')


def ensure_sdk(evidence, env, packages):
    sdk = Path(env.get('ANDROID_HOME') or env.get('ANDROID_SDK_ROOT') or '/missing-sdk')
    manager = sdk / 'cmdline-tools/latest/bin/sdkmanager'
    if not manager.is_file():
        raise RuntimeError('official_sdkmanager_missing')
    # stdin is DEVNULL; this never accepts a new license or invokes --licenses.
    run([manager, '--sdk_root=' + str(sdk), '--install', *packages], evidence / 'sdk-packages.log', env, timeout=900)
    return sdk


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--abi', choices=sorted(TARGETS), required=True)
    parser.add_argument('--evidence-dir', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    args = parser.parse_args()
    evidence, work = args.evidence_dir.resolve(), args.work_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True); work.mkdir(parents=True, exist_ok=True)
    before = tracked_inputs()
    result = dict(classification='INVALID', abi=args.abi, Android_runtime='NOT_RUN')
    try:
        source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT).strip():
            raise RuntimeError('unclean_source')
        env = dict(os.environ, MUYON_BRIDGE_BUILD_ID=source, CARGO_INCREMENTAL='0',
                   CARGO_TARGET_DIR=str(work / 'target'), CARGO_TERM_COLOR='never')
        sdk = ensure_sdk(evidence, env, ['ndk;' + NDK])
        ndk = sdk / 'ndk' / NDK
        properties = (ndk / 'source.properties').read_text()
        if not re.search(r'^Pkg.Revision\s*=\s*28\.2\.13676358\s*$', properties, re.M):
            raise RuntimeError('ndk_version')
        triple, clang_triple = TARGETS[args.abi]
        tools = ndk / 'toolchains/llvm/prebuilt/linux-x86_64/bin'
        linker = tools / (clang_triple + '26-clang')
        readelf = tools / 'llvm-readelf'
        env['CARGO_TARGET_' + triple.upper().replace('-', '_') + '_LINKER'] = str(linker)
        # Bundled readonly SQLite is C compiled for the same public API26 ABI.
        # cc-rs must never accidentally use the Linux host compiler for Android.
        env['CC_' + triple.replace('-', '_')] = str(linker)
        env['AR_' + triple.replace('-', '_')] = str(tools / 'llvm-ar')
        env['RUSTFLAGS'] = '-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384'
        run(['rustc', '--version'], evidence / 'rustc.log', env)
        if not (evidence / 'rustc.log').read_text().startswith('rustc 1.99.0 '):
            raise RuntimeError('pinned_rust_toolchain_missing')
        run([linker, '--version'], evidence / 'clang.log', env)
        run(['cargo', 'fetch', '--locked'], evidence / 'fetch.log', env)
        run(['cargo', 'build', '--offline', '--locked', '--release', '--lib', '--target', triple], evidence / 'link.log', env)
        library = evidence / 'libmuyon_android_contract_bridge.so'
        shutil.copyfile(work / 'target' / triple / 'release' / library.name, library)
        info = inspect(library.read_bytes(), args.abi)
        for option in ['--file-header', '--program-headers', '--dynamic', '--notes', '--dyn-syms']:
            run([readelf, option, '--wide', library], evidence / ('rust-' + option[2:] + '.log'), env)
        info['api26_import_compatibility'] = api26_imports(library, info, triple, ndk, readelf, evidence, env, 'rust')
        aar = work / 'jna.aar'; download(AAR_URL, aar, AAR_SHA)
        check_aar(aar, dict(aar_sha256=AAR_SHA, jni_sha256=JNI_SHA))
        jni = work / 'libjnidispatch.so'
        with zipfile.ZipFile(aar) as archive:
            jni.write_bytes(archive.read('jni/' + args.abi + '/libjnidispatch.so'))
        jna_info = inspect(jni.read_bytes(), args.abi, rust=False)
        jna_info['api26_import_compatibility'] = api26_imports(jni, jna_info, triple, ndk, readelf, evidence, env, 'jna')
        result.update(classification='GREEN', source_sha=source, build_identity=source, protocol=1,
            namespace='muyon_android_contract_bridge', min_api=26, shipping_features=[], rust_target=triple,
            library_sha256=sha(library), cargo_lock_sha256=sha(CORE / 'Cargo.lock'),
            android_config_sha256=sha(CORE / 'uniffi.android.toml'), ndk_version=NDK,
            ndk_properties_sha256=sha(ndk / 'source.properties'), clang_sha256=sha(linker.resolve()),
            readelf_sha256=sha(readelf), rust_elf=info, jna_elf=jna_info,
            jna_aar_sha256=AAR_SHA, jna_jni_sha256=sha(jni))
        return 0
    except Exception as failure:
        result['failure'] = type(failure).__name__ + ':' + str(failure)
        return 1
    finally:
        result['source_inputs_unchanged'] = before == tracked_inputs()
        if not result['source_inputs_unchanged']:
            result.update(classification='INVALID', failure='source_inputs_changed')
        (evidence / 'source-inputs.json').write_text(json.dumps(before, indent=2) + '\n')
        (evidence / 'manifest.json').write_text(json.dumps(result, indent=2) + '\n')
        summary = dict(result)
        for key in ['rust_elf', 'jna_elf']:
            if key in summary:
                summary[key] = {name: value for name, value in summary[key].items() if name != 'exported_symbols'}
                summary[key]['exported_symbol_count'] = len(result[key]['exported_symbols'])
        print('ANDROID_BRIDGE_ABI_MANIFEST ' + json.dumps(summary, sort_keys=True), flush=True)
        if not result['source_inputs_unchanged']:
            raise RuntimeError('source_inputs_changed')


if __name__ == '__main__':
    raise SystemExit(main())
