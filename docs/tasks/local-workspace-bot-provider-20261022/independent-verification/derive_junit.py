"""Derived failure-preserving JUnit from actual libtest stdout; not native XML."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
summary = []
for label in ['provider-targeted', 'core-full']:
    path = base / 'original' / (label + '.stdout.log')
    raw = path.read_bytes()
    text = raw.decode()
    totals = re.findall(r'test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored;', text)
    cases = re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', text, re.M)
    expected = sum(sum(int(n) for n in row[1:]) for row in totals)
    assert len(cases) == expected and expected > 0
    failed = sum(state == 'FAILED' for _, state in cases)
    ignored = sum(state == 'ignored' for _, state in cases)
    suite = ET.Element('testsuite', name=label, tests=str(len(cases)), failures=str(failed), errors='0', skipped=str(ignored))
    props = ET.SubElement(suite, 'properties')
    for name, value in [('origin', 'derived from raw libtest stdout; failures retained; invocations overlap'), ('raw_sha256', hashlib.sha256(raw).hexdigest())]:
        ET.SubElement(props, 'property', name=name, value=value)
    for name, state in cases:
        case = ET.SubElement(suite, 'testcase', classname=label, name=name)
        if state == 'FAILED':
            failure = ET.SubElement(case, 'failure', message='actual Rust test failure')
            marker = '---- ' + name + ' stdout ----'
            failure.text = text.split(marker, 1)[1].split('\n---- ', 1)[0].split('\nfailures:', 1)[0].strip() if marker in text else 'See sibling raw output.'
        elif state == 'ignored':
            ET.SubElement(case, 'skipped')
    ET.indent(suite)
    ET.ElementTree(suite).write(path.with_suffix('.junit.xml'), encoding='utf-8', xml_declaration=True)
    summary.append({'command':label,'executed':len(cases),'passed':len(cases)-failed-ignored,'failed':failed,'ignored':ignored,'failed_test_names':[name for name, state in cases if state == 'FAILED'],'test_names':[name for name, _ in cases]})
assert set(summary[0]['failed_test_names']) == set(summary[1]['failed_test_names'])
(base / 'test-summary.json').write_text(json.dumps({'invocations':summary,'ffi':'No tests executed: offline cache dependency failure, not a passing or failing native bridge test.','counting_note':'Targeted15 are inside partial core118; the same14 failures are not28 independent failures. Core command stopped early; later suites not executed.'},indent=2)+'\n')
print([(r['command'],r['passed'],r['failed'],r['executed']) for r in summary])
