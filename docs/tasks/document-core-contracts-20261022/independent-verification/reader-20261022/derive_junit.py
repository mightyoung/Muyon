"""Derived execution XML; external cleanup-tail RED overrides acceptance of green owner suites."""
import hashlib,json,pathlib,re,xml.etree.ElementTree as ET
base=pathlib.Path(__file__).resolve().parent
summary=[];maps={}
for label,relative in [('reader-targeted','original/reader-targeted'),('core-full','original/core-full'),('independent-probes','original/probes/probe-tests')]:
    path=base/(relative+'.stdout.log');raw=path.read_bytes();text=raw.decode();stderr=(base/(relative+'.stderr.log')).read_text();names=[]
    for line in stderr.splitlines():
        m=re.fullmatch(r'\s*Running (.+?) \((.+)\)',line)
        if m:names.append(m.group(1))
        elif line.strip().startswith('Doc-tests '):names.append(line.strip())
    starts=list(re.finditer(r'(?:^|\n)running (\d+) tests?\n',text))
    if label=='independent-probes':names=['External public Reader probes']
    assert len(starts)==len(names),(label,len(starts),len(names));groups=[]
    for i,start in enumerate(starts):
        chunk=text[start.end():starts[i+1].start() if i+1<len(starts) else len(text)];cases=re.findall(r'^test (.+) \.\.\. (ok|FAILED|ignored)$',chunk,re.M);assert len(cases)==int(start.group(1));groups.append({'binary':names[i],'cases':cases})
    total=sum(len(g['cases']) for g in groups);failed=sum(s=='FAILED' for g in groups for _,s in g['cases']);ignored=sum(s=='ignored' for g in groups for _,s in g['cases']);suite=ET.Element('testsuite',name=label,tests=str(total),failures=str(failed),errors='0',skipped=str(ignored));props=ET.SubElement(suite,'properties')
    for k,v in [('origin','derived from actual raw libtest; RED retained, not native runner XML'),('raw_sha256',hashlib.sha256(raw).hexdigest())]:ET.SubElement(props,'property',name=k,value=v)
    for g in groups:
        for name,state in g['cases']:
            case=ET.SubElement(suite,'testcase',classname=g['binary'],name=name)
            if state=='FAILED':
                f=ET.SubElement(case,'failure',message='Expected delivery rejection; actual original Reader returned success after cleanup expired grant');marker="thread '"+name+"'";f.text=stderr.split(marker,1)[1].split("\nthread '",1)[0].strip() if marker in stderr else stderr
            elif state=='ignored':ET.SubElement(case,'skipped')
        g['test_names']=[n for n,_ in g.pop('cases')]
    ET.indent(suite);ET.ElementTree(suite).write(path.with_suffix('.junit.xml'),encoding='utf-8',xml_declaration=True);summary.append({'command':label,'passed':total-failed-ignored,'failed':failed,'ignored':ignored,'groups':groups});maps[label]={g['binary']:set(g['test_names']) for g in groups}
lib=maps['core-full']['unittests src/lib.rs'];worker=maps['core-full']['unittests src/bin/business_worker.rs'];assert lib==worker and len(lib)==61;assert maps['reader-targeted']['unittests src/lib.rs'].issubset(lib)
(base/'test-summary.json').write_text(json.dumps({'invocations':summary,'shared_library_worker_source_test_count':61,'notes':['Owner Reader13 repeated in core library and worker; core266 execution count is not independent coverage.','Independent6 comprises4 pass and2 genuine cleanup-tail behavior RED. No author or product code changed.','Initial private API probe compile failure ran zero tests and is not a vulnerability reproduction.']},indent=2)+'\n');print([(r['command'],r['passed'],r['failed']) for r in summary])
