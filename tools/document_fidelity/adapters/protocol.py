"""Strict, authority-free host envelope for one numeric-cell operation."""
from decimal import Decimal, InvalidOperation
import re

IDENTITY_FIELDS = ('scope_id', 'file_id', 'base_revision', 'operation_id', 'idempotency_key')
REQUEST_KEYS = {'schema_version', 'source_sha256', 'operation', *IDENTITY_FIELDS}
LIMITS = dict(timeout_ms=30000, max_candidate_bytes=8*1024*1024, max_log_bytes=32768,
              cpu_seconds=20, address_space_bytes=512*1024*1024, max_pids=8,
              max_input_bytes=16*1024*1024)


def cell_address(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Z]{1,3}[1-9][0-9]{0,6}', value):
        raise ValueError('unsupported_cell_address')
    match = re.fullmatch(r'([A-Z]+)([0-9]+)', value)
    column = 0
    for char in match[1]:
        column = column*26 + ord(char)-64
    row = int(match[2])
    if column > 16384 or row > 1048576:
        raise ValueError('unsupported_cell_address')
    return row, column


def numeric(value):
    if (not isinstance(value, str) or len(value) > 32
            or not re.fullmatch(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?', value)
            or sum(c.isdigit() for c in value) > 15):
        raise ValueError('unsupported_numeric_value')
    try:
        return Decimal(value)
    except InvalidOperation as exc:
        raise ValueError('unsupported_numeric_value') from exc


def parse_request(raw):
    if type(raw) is not dict or set(raw) != REQUEST_KEYS:
        raise ValueError('invalid_request_fields')
    if type(raw['schema_version']) is not int or raw['schema_version'] != 1:
        raise ValueError('unsupported_schema')
    for field in IDENTITY_FIELDS:
        if not isinstance(raw[field], str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}', raw[field]):
            raise ValueError('invalid_identity')
    if not isinstance(raw['source_sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', raw['source_sha256']):
        raise ValueError('invalid_source_hash')
    op = raw['operation']
    if type(op) is not dict or set(op) != {'kind', 'sheet', 'cell', 'expected', 'replacement'}:
        raise ValueError('invalid_operation_fields')
    if op['kind'] != 'set_numeric_cell':
        raise ValueError('unsupported_operation')
    if (not isinstance(op['sheet'], str) or not 1 <= len(op['sheet']) <= 31
            or any(ord(c) < 32 or c in '[]:*?/\\' for c in op['sheet'])):
        raise ValueError('unsupported_sheet_name')
    cell_address(op['cell'])
    if numeric(op['expected']) == numeric(op['replacement']):
        raise ValueError('noop_operation')
    return {**{key: raw[key] for key in raw if key != 'operation'}, 'operation': dict(op)}
