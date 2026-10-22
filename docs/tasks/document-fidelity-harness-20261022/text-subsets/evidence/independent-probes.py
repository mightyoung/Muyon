from tools.document_fidelity.tests.test_text_subsets import build_complex_samples,subset_samples,rewrite,request,text_request,FakeExecutor,FakeTextExecutor
from tools.document_fidelity.adapters import runtime
cases=[]
s=build_complex_samples()['complex.xlsx']
s=rewrite(s,'xl/worksheets/sheet1.xml',lambda b:b.replace(b'<sheetData>',b'<sheetFormatPr defaultRowHeight="15"/><sheetFormatPr defaultRowHeight="0"/><sheetData>'))
cases.append(('duplicate sheetFormatPr',s,request(s),FakeExecutor()))
s=subset_samples()['simple-run.docx']
s=rewrite(s,'word/document.xml',lambda b:b.replace(b'Original </t>',b'Original <b/></t>'))
cases.append(('nested non-target w:t',s,text_request(s,'docx'),FakeTextExecutor()))
s=subset_samples()['simple-shape.pptx']
s=rewrite(s,'ppt/presentation.xml',lambda b:b.replace(b'<sldSz cx="9144000" cy="6858000"/>',b'<sldSz cx="9144000" cy="6858000"><p:timing xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/></sldSz>'))
cases.append(('nested presentation timing',s,text_request(s,'pptx'),FakeTextExecutor()))
for name,source,req,fake in cases:
 preview=runtime.preview_target(source,req)
 result=runtime.simulate_for_tests(source,req,fake)
 print(name, {'preview':preview,'status':result['status'],'fake_calls':len(fake.calls),'validation':result.get('validation',{}).get('status'),'real_status':runtime.run_real(source,req)['status']})
