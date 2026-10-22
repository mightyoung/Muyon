"""Derived per-binary execution evidence; repeated phases/probes are not coverage sums."""
import hashlib
import json
import pathlib
import re
import xml.etree.ElementTree as ET

base = pathlib.Path(__file__).resolve().parent
result = []
for phase in ['original', 'formatted']:
    phase_sets = {}
    for label, relative in [('provider-targeted', 'provider-targeted'), ('core-full', 'core-full'), ('external-probes', 'race/probe-tests')]:
        path = base / phase / (relative + '.stdout.log')
        raw = path.read_bytes()
        text = raw.decode()
        stderr = path.with_name(path.name.replace('.stdout.', '.stderr.')).read_text()
        names = []
        for line in stderr.splitlines():
            match = re.fullmatch(r'\s*Running (.+?) \((.+)\)', line)
            if match: names.append(match.group(1))
            elif line.strip().startswith('Doc-tests '): names.append(line.strip())
        starts = list(re.finditer(r'(?:^|\n)running (\d+) tests?\n', text))
        if label == 'external-probes': names = ['external core-API probes (not FFI)']
        assert len(starts) == len(names), (phase, label, len(starts), len(names))
        groups = []
        for i, start in enumerate(starts):
            chunk = text[start.end(): starts[i+1].start() if i+1<len(starts) else len(text)]
            cases = re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', chunk, re.M)
            assert len(cases) == int(start.group(1))
            groups.append({'binary': names[i], 'cases': cases})
        total = sum(len(g['cases']) for g in groups)
        failures = sum(status == 'FAILED' for g in groups for _,status in g['cases'])
        skipped = sum(status == 'ignored' for g in groups for _,status in g['cases'])
        suite = ET.Element('testsuite', name=phase+'/'+label, tests=str(total), failures=str(failures), errors='0', skipped=str(skipped))
        props = ET.SubElement(suite,'properties')
        for key, value in [('origin','derived libtest output; invocation/binary overlaps, not independent business cases'), ('raw_sha256',hashlib.sha256(raw).hexdigest())]: ET.SubElement(props,'property',name=key,value=value)
        for group in groups:
            for name,status in group['cases']:
                case=ET.SubElement(suite,'testcase',classname=group['binary'],name=name)
                if status=='FAILED': ET.SubElement(case,'failure',message='See raw output')
                elif status=='ignored': ET.SubElement(case,'skipped')
            group['test_names']=[name for name,_ in group.pop('cases')]
        ET.indent(suite);ET.ElementTree(suite).write(path.with_suffix('.junit.xml'),encoding='utf-8',xml_declaration=True)
        result.append({'phase':phase,'command':label,'passed':total-failures-skipped,'failed':failures,'ignored':skipped,'groups':groups})
        phase_sets[label]=set(n for g in groups for n in g['test_names'])
        if label=='core-full':
            mapping={g['binary']:set(g['test_names']) for g in groups}
            lib=mapping['unittests src/lib.rs'];worker=mapping['unittests src/bin/business_worker.rs']
            assert worker.issubset(lib)
            (base/phase/'binary-overlap.json').write_text(json.dumps({'library_tests':len(lib),'worker_tests':len(worker),'shared_source_names':sorted(lib & worker),'counting_note':'Shared direct-source worker cases are repeated execution contexts, not extra business coverage.'},indent=2)+'\n')
    assert phase_sets['provider-targeted'].issubset(phase_sets['core-full'])
(base/'test-summary.json').write_text(json.dumps({'invocations':result,'ffi':'Both real offline attempts blocked by missing anyhow1.0.104 before compilation; no FFI test execution/acceptance.','notes':['Provider26 is included in core209; phases are repeated, not additive.','External3 are diagnostic core-API probes; copied26 owner fixtures are filtered out.','lookup is a mutating terminal reconciliation, not a pure read.','32 races/phase are finite samples, not exhaustive interleaving proof.']},indent=2)+'\n')
print([(r['phase'],r['command'],r['passed'],r['failed']) for r in result])
