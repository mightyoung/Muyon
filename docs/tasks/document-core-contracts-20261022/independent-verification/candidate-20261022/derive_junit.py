"""Only executed libtest cases become derived JUnit; failed build is not a test run."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
summary = []
for label in ['pagination-targeted', 'candidate-targeted', 'history-targeted', 'text-label-targeted']:
    path = base / 'original' / (label + '.stdout.log')
    raw = path.read_bytes()
    text = raw.decode()
    totals = re.findall(r'test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored;', text)
    cases = re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', text, re.M)
    expected = sum(sum(int(n) for n in row[1:]) for row in totals)
    assert len(cases) == expected and expected > 0
    failed = sum(state == 'FAILED' for _, state in cases)
    skipped = sum(state == 'ignored' for _, state in cases)
    suite = ET.Element('testsuite', name=label, tests=str(len(cases)), failures=str(failed), errors='0', skipped=str(skipped))
    props = ET.SubElement(suite, 'properties')
    for name, value in [('origin', 'derived from actual libtest stdout; not native XML'), ('raw_sha256', hashlib.sha256(raw).hexdigest())]:
        ET.SubElement(props, 'property', name=name, value=value)
    for name, state in cases:
        case = ET.SubElement(suite, 'testcase', classname=label, name=name)
        if state == 'FAILED':
            ET.SubElement(case, 'failure', message='Consult original raw libtest output')
        elif state == 'ignored':
            ET.SubElement(case, 'skipped')
    ET.indent(suite)
    ET.ElementTree(suite).write(path.with_suffix('.junit.xml'), encoding='utf-8', xml_declaration=True)
    summary.append({'command':label,'passed':len(cases)-failed-skipped,'failed':failed,'ignored':skipped,'test_names':[name for name, _ in cases]})
assert set(summary[0]['test_names']).issubset(set(summary[1]['test_names']))
assert set(summary[3]['test_names']).issubset(set(summary[2]['test_names']))
assert not (base / 'original/core-full.stdout.log').read_bytes()
(base / 'test-summary.json').write_text(json.dumps({'invocations':summary,'core_full':'Compile failure exit101; zero test cases executed by this invocation. No fabricated JUnit pass.','counting_note':'Pagination1 is within candidate13; text-label1 is within history8. Repeated invocations and filtered-out cases are not additional independent scenarios.'},indent=2)+'\n')
print([(r['command'],r['passed'],r['failed']) for r in summary])
