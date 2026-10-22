"""Derived JUnit from retained libtest stdout; counts are per invocation, not additive."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
results = []
for label in ['storage-targeted', 'tail-hook-targeted', 'contracts-targeted', 'core-full']:
    raw = (base / (label + '.stdout.log')).read_bytes()
    text = raw.decode()
    totals = re.findall(r'test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored;', text)
    cases = re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', text, re.M)
    expected = sum(sum(int(n) for n in row[1:]) for row in totals)
    assert len(cases) == expected and expected > 0, (label, len(cases), expected)
    failed = sum(state == 'FAILED' for _, state in cases)
    skipped = sum(state == 'ignored' for _, state in cases)
    root = ET.Element('testsuite', name=label, tests=str(len(cases)), failures=str(failed), errors='0', skipped=str(skipped))
    props = ET.SubElement(root, 'properties')
    for name, value in [('origin', 'derived from retained libtest stdout; not native JUnit; invocations overlap'), ('raw_sha256', hashlib.sha256(raw).hexdigest())]:
        ET.SubElement(props, 'property', name=name, value=value)
    for name, state in cases:
        case = ET.SubElement(root, 'testcase', classname=label, name=name)
        if state == 'FAILED':
            ET.SubElement(case, 'failure', message='libtest FAILED; consult raw output')
        elif state == 'ignored':
            ET.SubElement(case, 'skipped')
    ET.indent(root)
    ET.ElementTree(root).write(base / (label + '.junit.xml'), encoding='utf-8', xml_declaration=True)
    results.append({'command':label, 'tests':len(cases), 'passed':len(cases)-failed-skipped, 'failed':failed, 'ignored':skipped, 'libtest_result_blocks':len(totals), 'test_names':[name for name, _ in cases], 'origin':'derived; invocation totals overlap'})
# Verify that repeated targeted runs are contained in the full run, not extra cases.
full = set(results[-1]['test_names'])
for row in results[:-1]:
    assert set(row['test_names']).issubset(full), row['command']
(base / 'test-summary.json').write_text(json.dumps({'invocations':results, 'counting_note':'Full-core total already includes storage15 + hook3 + contracts18. Targeted reruns are not additional scenarios.'},indent=2)+'\n')
print([(r['command'],r['passed'],r['failed']) for r in results])
