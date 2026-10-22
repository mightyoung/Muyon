"""Convert retained libtest text to derived JUnit; never native runner output."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
logs = list((base / 'historical').rglob('*.log')) + [base / 'fresh/tests.stdout.log']
summary = []
for path in sorted(logs):
    raw = path.read_bytes()
    content = raw.decode('utf-8')
    context = path.stem
    cases = []
    for line in content.splitlines():
        if line.lstrip().startswith('Running ') or line.lstrip().startswith('Doc-tests '):
            context = line.strip()
        match = re.fullmatch(r'test (.+) \.\.\. (ok|FAILED|ignored)(?:,.*)?', line)
        if match:
            cases.append((context, match.group(1), match.group(2)))
    totals = re.findall(r'test result: \w+\. (\d+) passed; (\d+) failed; (\d+) ignored;', content)
    expected = sum(sum(map(int, row)) for row in totals)
    assert cases and len(cases) == expected, (path, len(cases), expected)
    failed = sum(status == 'FAILED' for _, _, status in cases)
    ignored = sum(status == 'ignored' for _, _, status in cases)
    suite = ET.Element('testsuite', name=str(path.relative_to(base)), tests=str(len(cases)), failures=str(failed), errors='0', skipped=str(ignored))
    props = ET.SubElement(suite, 'properties')
    for name, value in [('origin', 'derived from retained raw libtest output; not native JUnit'), ('raw_sha256', hashlib.sha256(raw).hexdigest())]:
        ET.SubElement(props, 'property', name=name, value=value)
    for context, name, status in cases:
        case = ET.SubElement(suite, 'testcase', classname=context, name=name)
        if status == 'FAILED':
            failure = ET.SubElement(case, 'failure', message='libtest reported FAILED; see sibling raw log')
            marker = '---- ' + name + ' stdout ----'
            failure.text = content.split(marker, 1)[1].split('\n---- ', 1)[0].split('\nfailures:', 1)[0].strip() if marker in content else 'Failure details retained in raw log.'
        elif status == 'ignored':
            ET.SubElement(case, 'skipped')
    tree = ET.ElementTree(suite)
    ET.indent(tree)
    tree.write(path.with_suffix('.junit.xml'), encoding='utf-8', xml_declaration=True)
    summary.append({'raw_log':str(path.relative_to(base)), 'tests':len(cases),'passed':len(cases)-failed-ignored,'failed':failed,'ignored':ignored,'junit_origin':'derived, not native'})
(base / 'junit-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
