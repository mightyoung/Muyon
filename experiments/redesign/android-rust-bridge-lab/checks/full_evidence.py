"""Closed full-mode oracles, independent of native returned data."""
import re
from ffi_evidence import RUST_REACH

JVM_NAMES = [
    'native_handshake', 'bundled_metadata_positive', 'all_variants_repeat_identity_counts',
    'protocol_rejection_has_valid_siblings', 'request_id_bounds_have_valid_siblings',
]


def rust_full(raw, unit, integration):
    rows = re.findall(r'^test (\S+) \.\.\. (ok|FAILED|ignored)\s*$', raw, re.M)
    expected = {('tests::' + name, 'ok') for name in unit} | {(name, 'ok') for name in integration}
    summaries = re.findall(r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; (\d+) measured; (\d+) filtered out;', raw, re.M)
    return (len(rows) == len(expected) and set(rows) == expected
            and summaries == [('ok', '3', '0', '0', '0', '0'), ('ok', '6', '0', '0', '0', '0'), ('ok', '0', '0', '0', '0', '0')])


def jvm_full(raw, source, library_sha):
    mapped = f'ANDROID_BRIDGE_JVM_MAPPED source={source} sha256={library_sha}'
    lines = raw.splitlines()
    return lines == [mapped] + ['ANDROID_BRIDGE_JVM_PASS ' + name for name in JVM_NAMES]


def panic_full(raw, source, library_sha):
    mapped = f'ANDROID_BRIDGE_PANIC_MAPPED source={source} sha256={library_sha}'
    marker = 'ANDROID_BRIDGE_PANIC_ACTION_ENTERED'
    positive = 'ANDROID_BRIDGE_JVM_PASS panic_is_typed_and_valid_sibling_recovers'
    panics = re.findall(r"thread '([^']+)'(?: \(\d+\))? panicked at [^\n]+:\n([^\n]+)", raw)
    return (raw.count(mapped) == 1 and raw.count(marker) == 1 and raw.count(positive) == 1
            and raw.index(mapped) < raw.index(marker) < raw.index(positive)
            and panics == [('<unnamed>', 'ANDROID_BRIDGE_TEST_PANIC')]
            and 'Exception in thread' not in raw and RUST_REACH not in raw)
