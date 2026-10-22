"""Derived per-binary JUnit, with explicit direct-source worker duplication accounting."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
summary = []
all_groups = {}
for label in ['worker-tests', 'core-full']:
    raw = (base / (label + '.stdout.log')).read_bytes()
    stderr = (base / (label + '.stderr.log')).read_text()
    text = raw.decode()
    names = []
    for line in stderr.splitlines():
        match = re.fullmatch(r'\s*Running (.+?) \((.+)\)', line)
        if match:
            names.append(match.group(1))
        elif line.strip().startswith('Doc-tests '):
            names.append(line.strip())
    starts = list(re.finditer(r'(?:^|\n)running (\d+) tests?\n', text))
    assert len(starts) == len(names), (label, len(starts), len(names))
    groups = []
    for i, start in enumerate(starts):
        chunk = text[start.end():starts[i+1].start() if i+1 < len(starts) else len(text)]
        cases = re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', chunk, re.M)
        assert len(cases) == int(start.group(1)), (label, names[i])
        groups.append({'binary':names[i], 'test_names':[name for name, _ in cases], 'cases':cases})
    total = sum(len(group['cases']) for group in groups)
    failures = sum(state == 'FAILED' for group in groups for _, state in group['cases'])
    ignored = sum(state == 'ignored' for group in groups for _, state in group['cases'])
    root = ET.Element('testsuite', name=label, tests=str(total), failures=str(failures), errors='0', skipped=str(ignored))
    props = ET.SubElement(root, 'properties')
    for name, value in [('origin', 'derived from actual libtest output; per-binary execution counts, not unique scenario coverage'), ('raw_sha256', hashlib.sha256(raw).hexdigest())]:
        ET.SubElement(props, 'property', name=name, value=value)
    for group in groups:
        for name, state in group['cases']:
            case = ET.SubElement(root, 'testcase', classname=group['binary'], name=name)
            if state == 'FAILED':
                ET.SubElement(case, 'failure', message='See raw output')
            elif state == 'ignored':
                ET.SubElement(case, 'skipped')
        del group['cases']
    ET.indent(root)
    ET.ElementTree(root).write(base / (label + '.junit.xml'), encoding='utf-8', xml_declaration=True)
    summary.append({'command':label,'executed':total,'passed':total-failures-ignored,'failed':failures,'ignored':ignored,'groups':groups})
    all_groups[label] = {group['binary']:set(group['test_names']) for group in groups}
lib = all_groups['core-full']['unittests src/lib.rs']
worker = all_groups['core-full']['unittests src/bin/business_worker.rs']
assert lib == worker and len(lib) == 48
assert worker == all_groups['worker-tests']['unittests src/bin/business_worker.rs']
overlap = {'library_unit_count':len(lib),'worker_unit_count':len(worker),'identical_shared_source_names':sorted(lib & worker),'worker_separate_rerun_is_already_in_core_full':True,'core_full_total_is_execution_count_not_unique_scenarios':True,'note':'48 same source test functions compile/run in both library and standalone worker; standalone48 run repeats again in core-full. Do not add or call these independent business scenarios.'}
(base / 'test-summary.json').write_text(json.dumps({'invocations':summary,'duplication':overlap},indent=2)+'\n')
print([(row['command'],row['passed'],row['failed']) for row in summary]);print('shared library/worker source tests:',len(lib & worker))
