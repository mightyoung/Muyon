"""Bounded handoff of one genuine generated Android source through ordinary logs."""
import argparse
import base64
import binascii
import hashlib
import json
from pathlib import Path
import re
import sys

PREFIX = 'ANDROID_BRIDGE_BINDING_SOURCE '
RELATIVE = 'android/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt'
MAX_BYTES = 1048576
CHUNK_CHARS = 4096
MAX_RECORDS = ((((MAX_BYTES + 2) // 3) * 4 + CHUNK_CHARS - 1) // CHUNK_CHARS) + 2
PINS = {'source_sha', 'library_sha256', 'bindgen_sha256', 'android_config_sha256', 'android_binding_sha256'}
HEADER = PINS | {'kind', 'format_version', 'profile', 'path', 'bytes', 'chunks', 'chunk_chars'}


def pins(value):
    if not isinstance(value, dict) or set(value) != PINS:
        raise ValueError('binding_source_pins')
    for key, item in value.items():
        if not isinstance(item, str) or not re.fullmatch('[0-9a-f]{' + ('40' if key == 'source_sha' else '64') + '}', item):
            raise ValueError('binding_source_pins')


def validate_body(body, expected):
    if (not 0 < len(body) <= MAX_BYTES or b'\0' in body
            or hashlib.sha256(body).hexdigest() != expected['android_binding_sha256']):
        raise ValueError('binding_source_bytes_or_hash')
    try:
        body.decode('utf-8', errors='strict')
    except UnicodeError as failure:
        raise ValueError('binding_source_utf8') from failure


def emit(evidence, expected, output=sys.stdout):
    """No CLI file selector: the only emitted file is the fixed Android output."""
    pins(expected)
    path = evidence.resolve(strict=True)
    for part in Path(RELATIVE).parts:
        path = path / part
        if path.is_symlink():
            raise ValueError('binding_source_symlink')
    if not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError('binding_source_size')
    with path.open('rb') as source:
        body = source.read(MAX_BYTES + 1)
    validate_body(body, expected)
    encoded = base64.b64encode(body).decode('ascii')
    chunks = [encoded[index:index + CHUNK_CHARS] for index in range(0, len(encoded), CHUNK_CHARS)]
    header = dict(expected, kind='manifest', format_version=1, profile='android', path=RELATIVE,
                  bytes=len(body), chunks=len(chunks), chunk_chars=CHUNK_CHARS)
    records = [header] + [dict(kind='chunk', index=index, data=data) for index, data in enumerate(chunks)]
    records.append(dict(kind='end', bytes=len(body), chunks=len(chunks),
                        android_binding_sha256=expected['android_binding_sha256']))
    # Nothing is printed before all source/provenance/size checks have succeeded.
    for record in records:
        print(PREFIX + json.dumps(record, sort_keys=True, separators=(',', ':')), file=output, flush=True)


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('binding_source_duplicate_key')
        value[key] = item
    return value


def decode(log, expected):
    pins(expected)
    records = []
    for line in log.splitlines():
        if PREFIX not in line:
            continue
        if len(records) >= MAX_RECORDS:
            raise ValueError('binding_source_record_budget')
        before, payload = line.split(PREFIX, 1)
        if (len(payload) > CHUNK_CHARS + 2048 or (before and not re.fullmatch(
                r'[^\t\n]+\t[^\t\n]+\t\ufeff?\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ', before))):
            raise ValueError('binding_source_log_envelope')
        try:
            record = json.loads(payload, object_pairs_hook=unique_object)
        except (ValueError, RecursionError) as failure:
            raise ValueError('binding_source_json') from failure
        if not isinstance(record, dict):
            raise ValueError('binding_source_record')
        records.append(record)
    if len(records) < 3:
        raise ValueError('binding_source_incomplete')
    header, end = records[0], records[-1]
    if (set(header) != HEADER or header['kind'] != 'manifest' or type(header['format_version']) is not int
            or header['format_version'] != 1 or header['profile'] != 'android' or header['path'] != RELATIVE
            or any(header[key] != value for key, value in expected.items())
            or type(header['bytes']) is not int or not 0 < header['bytes'] <= MAX_BYTES
            or type(header['chunks']) is not int or type(header['chunk_chars']) is not int
            or header['chunk_chars'] != CHUNK_CHARS):
        raise ValueError('binding_source_manifest')
    encoded_length = ((header['bytes'] + 2) // 3) * 4
    count = (encoded_length + CHUNK_CHARS - 1) // CHUNK_CHARS
    if (header['chunks'] != count or len(records) != count + 2
            or end != dict(kind='end', bytes=header['bytes'], chunks=count,
                           android_binding_sha256=expected['android_binding_sha256'])
            or type(end.get('bytes')) is not int or type(end.get('chunks')) is not int):
        raise ValueError('binding_source_count_or_end')
    chunks = []
    for index, record in enumerate(records[1:-1]):
        length = CHUNK_CHARS if index < count - 1 else encoded_length - CHUNK_CHARS * index
        if (set(record) != {'kind', 'index', 'data'} or record['kind'] != 'chunk'
                or type(record['index']) is not int or record['index'] != index
                or not isinstance(record['data'], str) or len(record['data']) != length):
            raise ValueError('binding_source_chunk')
        chunks.append(record['data'])
    joined = ''.join(chunks)
    try:
        body = base64.b64decode(joined, validate=True)
    except (ValueError, binascii.Error) as failure:
        raise ValueError('binding_source_base64') from failure
    if len(body) != header['bytes'] or base64.b64encode(body).decode('ascii') != joined:
        raise ValueError('binding_source_length_or_encoding')
    validate_body(body, expected)
    return body, header


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    for flag in ['source', 'library-sha256', 'bindgen-sha256', 'config-sha256', 'binding-sha256']:
        parser.add_argument('--expected-' + flag, required=True)
    args = parser.parse_args()
    expected = dict(source_sha=args.expected_source, library_sha256=args.expected_library_sha256,
        bindgen_sha256=args.expected_bindgen_sha256, android_config_sha256=args.expected_config_sha256,
        android_binding_sha256=args.expected_binding_sha256)
    try:
        root = Path(__file__).resolve().parents[4]
        if not args.output.is_absolute() or args.output.resolve().is_relative_to(root):
            raise ValueError('binding_source_output_must_be_external')
        body, header = decode(args.log.read_text(encoding='utf-8'), expected)
        with args.output.open('xb') as output:
            output.write(body)
        print('ANDROID_BRIDGE_BINDING_SOURCE_VALID ' + json.dumps(header, sort_keys=True))
        return 0
    except (ValueError, OSError) as failure:
        print('ANDROID_BRIDGE_BINDING_SOURCE_INVALID ' + type(failure).__name__, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
