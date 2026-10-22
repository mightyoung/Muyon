import sys, io, json, zipfile, hashlib, subprocess
from pathlib import Path
sys.path.insert(0, '/workspace/document-fidelity')
from tools.document_fidelity.adapters import xlsx, runtime
from tools.document_fidelity.tests.test_adapter import request, edit_bytes, FakeExecutor
from tools.document_fidelity.complex_fixtures import build_complex_samples
base=build_complex_samples()['complex.xlsx']; target='xl/worksheets/sheet1.xml'
def parts(data):
    with zipfile.ZipFile(io.BytesIO(data)) as z: return {n:z.read(n) for n in z.namelist()}
def pack(p):
    o=io.BytesIO()
    with zipfile.ZipFile(o,'w',zipfile.ZIP_DEFLATED) as z:
        for n,b in p.items(): z.writestr(n,b)
    return o.getvalue()
def change(data, name, fn):
    p=parts(data); p[name]=fn(p[name]); return pack(p)
def inspect_source(label,data):
    try: xlsx.prepare(data,request(data)); result='ACCEPTED'
    except Exception as e: result=type(e).__name__+':'+str(e)
    return label,result
results=[]
# Preserve identical single PI text/order, relocate it from before root to after root.
pi=b'<?xml-stylesheet type="text/xsl" href="local.xsl"?>'
p=parts(base); original=p[target]
# Avoid placing PI before an XML declaration.
if original.startswith(b'<?xml'): original=original.split(b'?>',1)[1]
p[target]=pi+original; source=pack(p)
p[target]=original.replace(b'<v>2</v>',b'<v>5</v>',1)+pi
candidate=pack(p)
plan=xlsx.prepare(source,request(source)); verdict=xlsx.validate_candidate(plan,candidate)
results.append(['relocated_prolog_pi',verdict])
Path('/tmp/adapter-pi-source.xlsx').write_bytes(source); Path('/tmp/adapter-pi-candidate.xlsx').write_bytes(candidate)
for name,fn in [
 ('protected',lambda b:b.replace(b'</worksheet>',b'<sheetProtection sheet="1"/></worksheet>')),
 ('unknown_namespace',lambda b:b.replace(b'</worksheet>',b'<e:unknown xmlns:e="urn:unknown"/></worksheet>')),
 ('namespace_attribute',lambda b:b.replace(b'<worksheet ',b'<worksheet xmlns:e="urn:unknown" e:mode="a" ')),
 ('hidden_row',lambda b:b.replace(b'<row r="1">',b'<row r="1" hidden="1">')),
 ('hidden_column',lambda b:b.replace(b'<sheetData>',b'<cols><col min="1" max="1" hidden="1"/></cols><sheetData>')),
]: results.append(inspect_source(name,change(base,target,fn)))
plan=xlsx.prepare(base,request(base))
for label,b in [('corrupt',b'PKbad'),('malformed_target',change(edit_bytes(base),target,lambda b:b'<bad')),('oversized',b'x'*(16*1024*1024+1))]: results.append([label,xlsx.validate_candidate(plan,b)])
for admission in [True,1,'pass',['pass'],{}]:
    try: r=runtime.run_real(base,request(base),admission); results.append(['admission_'+repr(admission),r])
    except Exception as e: results.append(['admission_'+repr(admission),'RAISED '+type(e).__name__+':'+str(e)])
fixtures=[]
root=Path('/workspace/document-fidelity')
for directory in ['fixtures','fixtures_complex']:
    manifest=json.loads((root/'tools/document_fidelity'/directory/'manifest.json').read_text())
    for name,entry in manifest.items():
        p=root/'tools/document_fidelity'/directory/name
        digest=hashlib.sha256(p.read_bytes()).hexdigest()
        expected=entry.get('source',entry)['sha256']
        relative=str(p.relative_to(root))
        prior=subprocess.check_output(['git','show','7037166d4f1154ebbb38bdaea158b6ac4f8b544a:'+relative],cwd=root)
        fixtures.append(dict(path=relative,sha256=digest,manifest_match=digest==expected,base_bytes_unchanged=prior==p.read_bytes()))
output=dict(results=results,fixtures=fixtures,engine_imported='openpyxl' in sys.modules)
Path('/tmp/adapter-independent-probes.json').write_text(json.dumps(output,indent=2))
for label,result in results: print(label, json.dumps(result)[:450])
print('fixtures',json.dumps(fixtures)); print('engine_imported',output['engine_imported'])
