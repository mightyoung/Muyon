"""Derived per-version/per-binary execution evidence; sources and overlaps stay separate."""
import hashlib,json,pathlib,re,xml.etree.ElementTree as ET
base=pathlib.Path(__file__).resolve().parent;summary=[];overlaps=[]
for phase in ['pure-tail','performance','pure-tail-formatted','performance-formatted']:
    labels=[('reader-targeted','reader-targeted'),('core-full','core-full'),('old-six-probes','probes/probe-tests')]
    if phase.startswith('performance'):labels.insert(0,('snapshot-cost','snapshot-cost'))
    sets={}
    for label,relative in labels:
        p=base/phase/(relative+'.stdout.log');raw=p.read_bytes();text=raw.decode();stderr=(base/phase/(relative+'.stderr.log')).read_text();names=[]
        for line in stderr.splitlines():
            m=re.fullmatch(r'\s*Running (.+?) \((.+)\)',line)
            if m:names.append(m.group(1))
            elif line.strip().startswith('Doc-tests '):names.append(line.strip())
        starts=list(re.finditer(r'(?:^|\n)running (\d+) tests?\n',text))
        if label=='old-six-probes':names=['Unchanged external Reader regressions']
        assert len(starts)==len(names),(phase,label,len(starts),len(names));groups=[]
        for i,start in enumerate(starts):
            chunk=text[start.end():starts[i+1].start() if i+1<len(starts) else len(text)];cases=re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$',chunk,re.M);assert len(cases)==int(start.group(1));groups.append({'binary':names[i],'cases':cases})
        n=sum(len(g['cases']) for g in groups);failed=sum(s=='FAILED' for g in groups for _,s in g['cases']);ignored=sum(s=='ignored' for g in groups for _,s in g['cases']);suite=ET.Element('testsuite',name=phase+'/'+label,tests=str(n),failures=str(failed),errors='0',skipped=str(ignored));props=ET.SubElement(suite,'properties')
        for k,v in [('origin','derived actual libtest output; version/binary overlaps not added as coverage'),('raw_sha256',hashlib.sha256(raw).hexdigest())]:ET.SubElement(props,'property',name=k,value=v)
        for g in groups:
            for name,state in g['cases']:
                case=ET.SubElement(suite,'testcase',classname=g['binary'],name=name)
                if state=='FAILED':ET.SubElement(case,'failure',message='See raw output')
                elif state=='ignored':ET.SubElement(case,'skipped')
            g['test_names']=[name for name,_ in g.pop('cases')]
        ET.indent(suite);ET.ElementTree(suite).write(p.with_suffix('.junit.xml'),encoding='utf-8',xml_declaration=True);summary.append({'phase':phase,'command':label,'passed':n-failed-ignored,'failed':failed,'ignored':ignored,'groups':groups});sets[label]=set(n for g in groups for n in g['test_names'])
        if label=='core-full':
            mapping={g['binary']:set(g['test_names']) for g in groups};lib=mapping['unittests src/lib.rs'];worker=mapping['unittests src/bin/business_worker.rs'];assert lib==worker;overlaps.append({'phase':phase,'same_source_library_worker_count':len(lib),'shared_names':sorted(lib),'core_total_is_execution_count_not_unique_scenarios':True})
    assert sets['reader-targeted'].issubset(sets['core-full'])
    if phase.startswith('performance'):assert sets['snapshot-cost'].issubset(sets['reader-targeted'])
(base/'test-summary.json').write_text(json.dumps({'invocations':summary,'binary_overlaps':overlaps,'notes':['Same six external probes as original ff3cc, including both genuine59-byte RED regressions.','Reader/cost/worker duplication and repeated versions are not added as independent coverage.','Pure-tail contains no snapshot performance claim.']},indent=2)+'\n');print([(r['phase'],r['command'],r['passed'],r['failed']) for r in summary])
