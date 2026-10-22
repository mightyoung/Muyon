# Original synthetic reference vectors for the published expanded-tree-json-v1 spec.
import json,hashlib,pathlib
cases=[
 ('null-empty',['{urn:test}r',[],None,'',[]]),
 ('unicode-attributes',['{urn:文}r',[['{urn:z}字','文😀'],['a','é'],['Z','line\n\t\r\b\f\x00\x1f\x7f"\\/']], '中é😀𝄞',None,[]]),
 ('special-nodes',['{urn:test}r',[['z','last'],['a','first']],None,None,[['#comment',[],'unchanged comment',None,[]],['#pi',[],'target instruction','尾',[]],['{urn:test}t',[],'',None,[]]]]),
 ('docx-run',['{http://schemas.openxmlformats.org/wordprocessingml/2006/main}r',[],None,None,[['{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t',[],'target',None,[]]]]),
 ('pptx-run',['{http://schemas.openxmlformats.org/drawingml/2006/main}r',[],None,None,[['{http://schemas.openxmlformats.org/drawingml/2006/main}t',[],'target',None,[]]]]),
]
def norm(n):return [n[0],sorted(n[1]),n[2],n[3],[norm(c) for c in n[4]]]
rows=[]
for name,form in cases:
 raw=json.dumps(norm(form),ensure_ascii=True,separators=(',',':'))
 rows.append(dict(name=name,form=form,canonical=raw,sha256=hashlib.sha256(raw.encode()).hexdigest()))
p=pathlib.Path('crates/muyon-core/tests/document_edit_tree_goldens.json');p.write_text(json.dumps(rows,ensure_ascii=True,indent=2)+'\n')
print(json.dumps([{k:r[k] for k in ('name','sha256')} for r in rows],indent=2))
