"""Derived JUnit from verbatim libtest stdout, not native runner XML."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
results = []
for label in ['targeted', 'core-full']:
    path = base / (label + '.stdout.log')
    raw = path.read_bytes()
    text = raw.decode()
    totals = re.findall(r'test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored;', text)
    cases = re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', text, re.M)
    expected = sum(sum(int(n) for n in row[1:]) for row in totals)
    assert len(cases) == expected and expected > 0, (label, len(cases), expected)
    failed = sum(state == 'FAILED' for _, state in cases)
    skipped = sum(state == 'ignored' for _, state in cases)
    root = ET.Element('testsuite', name=label, tests=str(len(cases)), failures=str(failed), errors='0', skipped=str(skipped))
    props = ET.SubElement(root, 'properties')
    for name, value in [('origin', 'derived from retained libtest stdout; not native JUnit'), ('raw_sha256', hashlib.sha256(raw).hexdigest())]:
        ET.SubElement(props, 'property', name=name, value=value)
    for name, state in cases:
        case = ET.SubElement(root, 'testcase', classname=label, name=name)
        if state == 'FAILED':
            ET.SubElement(case, 'failure', message='libtest FAILED; consult original stdout')
        elif state == 'ignored':
            ET.SubElement(case, 'skipped')
    ET.indent(root)
    ET.ElementTree(root).write(base / (label + '.junit.xml'), encoding='utf-8', xml_declaration=True)
    results.append({'command':label,'tests':len(cases),'passed':len(cases)-failed-skipped,'failed':failed,'ignored':skipped,'libtest_result_blocks':len(totals),'origin':'derived, not native'})
(base / 'test-summary.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(results, indent=2))
