"""One stdlib-only private packaging verifier shared by CI and optional Gradle input."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[4]
SCHEMA = Path('docs/design/ANDROID-RUST-BRIDGE-INPUTS-V1.schema.json')
SCHEMA_SHA = '1e47b50edc6e85e352e5d931e10c7a1ef18f0b4b85b112e17bf71664c4a1bece'
BINDING = Path('experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt')
CONFIG = Path('experiments/redesign/android-rust-bridge-lab/core/uniffi.android.toml')
ABIS = ('arm64-v8a', 'x86_64')


class Invalid(ValueError):
    pass


def fail(code):
    raise Invalid(code)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            fail('duplicate_key')
        result[key] = value
    return result


def decode(raw):
    try:
        return json.loads(raw.decode('utf-8'), object_pairs_hook=pairs,
                          parse_constant=lambda _: fail('json_constant'))
    except (UnicodeError, json.JSONDecodeError):
        fail('json')


def validate(value, spec, definitions):
    if '$ref' in spec:
        prefix = '#/$defs/'
        if not spec['$ref'].startswith(prefix):
            fail('schema')
        return validate(value, definitions[spec['$ref'][len(prefix):]], definitions)
    kind = spec['type']
    if kind == 'object':
        if type(value) is not dict or set(value) != set(spec['required']):
            fail('manifest_shape')
        for key, child in spec['properties'].items():
            validate(value[key], child, definitions)
    elif kind == 'integer':
        if type(value) is not int:
            fail('manifest_type')
    elif kind == 'string':
        if type(value) is not str:
            fail('manifest_type')
        if 'minLength' in spec and not spec['minLength'] <= len(value) <= spec['maxLength']:
            fail('manifest_hash_format')
        if 'pattern' in spec and re.fullmatch(spec['pattern'], value) is None:
            fail('manifest_hash_format')
    else:
        fail('schema')
    if 'const' in spec and value != spec['const']:
        fail('manifest_constant')


def regular(path):
    if path.is_symlink() or not path.is_file():
        fail('regular_file')


def check_aar(path, expected):
    regular(path)
    if digest(path) != expected['aar_sha256']:
        fail('jna_aar_hash')
    try:
        with zipfile.ZipFile(path) as archive:
            for abi in ABIS:
                entry = f'jni/{abi}/libjnidispatch.so'
                if archive.namelist().count(entry) != 1:
                    fail('jna_jni_entry')
                if hashlib.sha256(archive.read(entry)).hexdigest() != expected['jni_sha256'][abi]:
                    fail('jna_jni_hash')
    except (zipfile.BadZipFile, KeyError, RuntimeError):
        fail('jna_zip')


def verify(input_root, expected_source_sha, binding, android_config, jna_aar):
    if re.fullmatch(r'[0-9a-f]{40}', expected_source_sha) is None:
        fail('expected_source_format')
    if not input_root.is_absolute() or input_root.is_symlink() or not input_root.is_dir():
        fail('input_root')
    for supplied, fixed in [(binding, BINDING), (android_config, CONFIG)]:
        if not supplied.is_absolute() or supplied.resolve() != (ROOT / fixed).resolve():
            fail('fixed_source_path')
        regular(supplied)
    if not jna_aar.is_absolute():
        fail('jna_path')
    schema_path = ROOT / SCHEMA
    if digest(schema_path) != SCHEMA_SHA:
        fail('schema_identity')
    schema = decode(schema_path.read_bytes())
    manifest = input_root / 'bridge-inputs.json'
    regular(manifest)
    if manifest.stat().st_size > 65536:
        fail('manifest_limit')
    value = decode(manifest.read_bytes())
    validate(value, schema, schema['$defs'])
    if value['source_sha'] != expected_source_sha or value['build_identity'] != expected_source_sha:
        fail('source_identity')
    if digest(binding) != value['android_binding_sha256']:
        fail('binding_hash')
    if digest(android_config) != value['android_config_sha256']:
        fail('android_config_hash')
    expected_files = {'bridge-inputs.json'}
    expected_dirs = {'jniLibs', *(f'jniLibs/{abi}' for abi in ABIS)}
    for entry in input_root.rglob('*'):
        name = entry.relative_to(input_root).as_posix()
        if entry.is_symlink():
            fail('input_tree')
        if entry.is_dir():
            if name not in expected_dirs:
                fail('input_tree')
        elif not entry.is_file():
            fail('input_tree')
    expected_files.update(value['rust_libraries'][abi]['path'] for abi in ABIS)
    actual_files = {entry.relative_to(input_root).as_posix() for entry in input_root.rglob('*') if entry.is_file()}
    actual_dirs = {entry.relative_to(input_root).as_posix() for entry in input_root.rglob('*') if entry.is_dir()}
    if actual_files != expected_files or actual_dirs != expected_dirs:
        fail('input_tree')
    for abi in ABIS:
        record = value['rust_libraries'][abi]
        path = input_root / record['path']
        regular(path)
        if digest(path) != record['sha256']:
            fail('rust_library_hash')
    check_aar(jna_aar, value['jna'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input-root', type=Path, required=True)
    parser.add_argument('--expected-source-sha', required=True)
    parser.add_argument('--binding', type=Path, required=True)
    parser.add_argument('--android-config', type=Path, required=True)
    parser.add_argument('--jna-aar', type=Path, required=True)
    args = parser.parse_args()
    try:
        verify(args.input_root, args.expected_source_sha, args.binding, args.android_config, args.jna_aar)
    except Invalid as error:
        print('BRIDGE_INPUTS_INVALID ' + str(error), file=sys.stderr)
        return 1
    except (OSError, KeyError, TypeError, ValueError):
        print('BRIDGE_INPUTS_INVALID io_or_schema', file=sys.stderr)
        return 1
    print('BRIDGE_INPUTS_VALID')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
