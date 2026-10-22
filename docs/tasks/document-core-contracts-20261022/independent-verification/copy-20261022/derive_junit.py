"""Derived JUnit from retained libtest stdout; repeated phases are not extra scenarios."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
summary = []
for phase in ['original', 'formatted']:
    rows = []
    for label in ['copy-targeted', 'document-hooks', 'core-full']:
        path = base / phase / (label + '.stdout.log')
        raw = path.read_bytes()
        text = raw.decode()
        totals = re.findall(r'test result: (\w+)\. (\d+) passed; (\d+) failed; (\d+) ignored;', text)
        cases = re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', text, re.M)
        expected = sum(sum(int(n) for n in row[1:]) for row in totals)
        assert len(cases) == expected and expected > 0, (phase, label, len(cases), expected)
        failed = sum(state == 'FAILED' for _, state in cases)
        skipped = sum(state == 'ignored' for _, state in cases)
        suite = ET.Element('testsuite', name=phase + '/' + label, tests=str(len(cases)), failures=str(failed), errors='0', skipped=str(skipped))
        props = ET.SubElement(suite, 'properties')
        for name, value in [('origin', 'derived from retained libtest stdout; not native runner XML'), ('raw_sha256', hashlib.sha256(raw).hexdigest())]:
            ET.SubElement(props, 'property', name=name, value=value)
        for name, state in cases:
            case = ET.SubElement(suite, 'testcase', classname=label, name=name)
            if state == 'FAILED':
                ET.SubElement(case, 'failure', message='libtest FAILED; consult original raw output')
            elif state == 'ignored':
                ET.SubElement(case, 'skipped')
        ET.indent(suite)
        ET.ElementTree(suite).write(path.with_suffix('.junit.xml'), encoding='utf-8', xml_declaration=True)
        rows.append({'phase':phase,'command':label,'passed':len(cases)-failed-skipped,'failed':failed,'ignored':skipped,'test_names':[name for name, _ in cases]})
    assert set(rows[0]['test_names']).issubset(set(rows[1]['test_names']))
    assert set(rows[1]['test_names']).issubset(set(rows[2]['test_names']))
    summary.extend(rows)
(base / 'test-summary.json').write_text(json.dumps({'invocations':summary,'counting_note':'COPY6 are inside hooks9, inside core full189. Targeted repeats and original/formatted repeated invocations are not added as independent scenarios.'},indent=2)+'\n')
print([(r['phase'],r['command'],r['passed'],r['failed']) for r in summary])
