"""Original synthetic packages, standard-library/fake-only tests."""
import hashlib,io,json,unittest,zipfile
import xml.etree.ElementTree as ET
from tools.document_fidelity.complex_fixtures import build_complex_samples
from tools.document_fidelity.adapters import xlsx,runtime
from tools.document_fidelity.tests.test_adapter import request,FakeExecutor,edit_bytes


def rewrite(data,part,transform):
    with zipfile.ZipFile(io.BytesIO(data)) as z:payloads={n:z.read(n) for n in z.namelist()}
    payloads[part]=transform(payloads[part])
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
        for name,payload in payloads.items():z.writestr(name,payload)
    return out.getvalue()

class PreviewTests(unittest.TestCase):
    def setUp(self):self.data=build_complex_samples()['complex.xlsx']
    def test_preview_visible_target_and_lexical_values(self):
        r=xlsx.preview(self.data,request(self.data))
        self.assertEqual('supported',r['status'])
        self.assertEqual({'sheet':False,'row':False,'column':False},r['hidden'])
        self.assertFalse(r['protected']);self.assertFalse(r['merged'])
        self.assertEqual('2',r['old_value']);self.assertEqual('5',r['new_value'])
        self.assertEqual('Original',r['sheet']);self.assertEqual('A1',r['cell'])
    def test_hidden_protected_and_merged_preview_blocks_fake_dispatch(self):
        cases=[('row',lambda b:b.replace(b'<row r="1">',b'<row r="1" hidden="1">')),
               ('column',lambda b:b.replace(b'<sheetData>',b'<cols><col min="1" max="1" hidden="true"/></cols><sheetData>')),
               ('protected',lambda b:b.replace(b'</worksheet>',b'<sheetProtection sheet="1"/></worksheet>')),
               ('merged',lambda b:b.replace(b'ref="A3:B3"',b'ref="A1:B1"'))]
        for label,fn in cases:
            with self.subTest(label=label):
                data=rewrite(self.data,'xl/worksheets/sheet1.xml',fn);req=request(data)
                r=xlsx.preview(data,req);self.assertEqual('unsupported',r['status'],r)
                if label in ('row','column'):self.assertTrue(r['hidden'][label])
                else:self.assertTrue(r[label])
                f=FakeExecutor();out=runtime.simulate_for_tests(data,req,f)
                self.assertEqual('rejected',out['status']);self.assertFalse(f.calls)
    def test_hidden_sheet_preview_and_unchanged_decimal_serialization_rule(self):
        data=rewrite(self.data,'xl/workbook.xml',lambda b:b.replace(b'name="Original"',b'name="Original" state="hidden"'))
        r=xlsx.preview(data,request(data));self.assertTrue(r['hidden']['sheet']);self.assertEqual('unsupported',r['status'])
        req=request(self.data);req['operation']['replacement']='5.0'
        plan=xlsx.prepare(self.data,req)
        self.assertEqual('fail',xlsx.validate_candidate(plan,edit_bytes(self.data))['status'])



from tools.document_fidelity.subset_fixtures import build_samples as subset_samples
from tools.document_fidelity.adapters.protocol import parse_request

W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
P='http://schemas.openxmlformats.org/presentationml/2006/main'
A='http://schemas.openxmlformats.org/drawingml/2006/main'

def text_request(source,kind):
    from tools.document_fidelity.adapters.text_common import local_fingerprint
    r=request(source);r['schema_version']=2
    part='word/document.xml' if kind=='docx' else 'ppt/slides/slide1.xml'
    with zipfile.ZipFile(io.BytesIO(source)) as z:root=ET.fromstring(z.read(part),parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True,insert_pis=True)))
    run=root.findall(f'{{{W}}}body/{{{W}}}p')[0].findall(f'{{{W}}}r')[1] if kind=='docx' else root.find(f'.//{{{A}}}r')
    if kind=='docx':r['operation']=dict(kind='replace_docx_run_text',paragraph_index=0,run_index=1,expected='target',replacement='edited')
    else:r['operation']=dict(kind='replace_pptx_shape_text',slide_id=256,shape_id=2,paragraph_index=0,run_index=0,expected='target',replacement='edited')
    r['operation'].update(part=part,target_sha256=local_fingerprint(run))
    return r

class FakeTextExecutor:
    kind='fake_executor'
    def __init__(self,mode='ok'):self.mode=mode;self.calls=[]
    def execute(self,launch,input_path,output_path,job_path):
        self.calls.append(launch);job=json.loads(job_path.read_text());fmt=launch['format']
        part='word/document.xml' if fmt=='docx' else 'ppt/slides/slide1.xml'
        data=input_path.read_bytes()
        def edit(payload):
            root=ET.fromstring(payload,parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True,insert_pis=True)))
            if fmt=='docx':
                runs=root.findall(f'{{{W}}}body/{{{W}}}p')[0].findall(f'{{{W}}}r')
                runs[1].find(f'{{{W}}}t').text='edited'
                if self.mode=='other':runs[0].find(f'{{{W}}}t').text='wrong'
            else:
                root.find(f'.//{{{A}}}t').text='edited'
                if self.mode=='other':root.find(f'.//{{{P}}}cNvPr').set('name','wrong')
            return ET.tostring(root)
        result=rewrite(data,part,edit)
        if self.mode=='unknown':result=rewrite(result,'custom/original.bin',lambda _:b'changed')
        if self.mode=='drop':
            with zipfile.ZipFile(io.BytesIO(result)) as z:parts={n:z.read(n) for n in z.namelist() if n!='custom/original.bin'}
            out=io.BytesIO()
            with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
                for n,payload in parts.items():z.writestr(n,payload)
            result=out.getvalue()
        output_path.write_bytes(result)
        return dict(status='exited',exit_code=0,elapsed_ms=1,stdout=b'',stderr=b'')

class TextSubsetTests(unittest.TestCase):
    def test_explicit_v2_text_and_v1_numeric_compatibility(self):
        for fmt,source in [('docx',subset_samples()['simple-run.docx']),('pptx',subset_samples()['simple-shape.pptx'])]:
            r=text_request(source,fmt);self.assertEqual(r,parse_request(r))
            r['schema_version']=1
            with self.assertRaises(ValueError):parse_request(r)
        self.assertEqual(1,parse_request(request(build_complex_samples()['complex.xlsx']))['schema_version'])
    def test_simple_text_preview_and_fake_pipeline(self):
        for fmt,name in [('docx','simple-run.docx'),('pptx','simple-shape.pptx')]:
            with self.subTest(fmt=fmt):
                source=subset_samples()[name];r=text_request(source,fmt)
                f=FakeTextExecutor();out=runtime.simulate_for_tests(source,r,f)
                self.assertEqual('simulated_validated',out['status'],out)
                self.assertEqual(2,out['schema_version']);self.assertEqual('target',out['preview']['old_value'])
                self.assertEqual('edited',out['preview']['new_value']);self.assertEqual('supported',out['preview']['status'])
                self.assertEqual('pass',out['validation']['status']);self.assertEqual('not_run',out['real_roundtrip'])
                self.assertEqual(fmt,f.calls[0]['format']);self.assertTrue(str(f.calls[0]['input']).endswith('.'+fmt))
                self.assertEqual('held',runtime.run_real(source,r)['status'])
    def test_non_target_node_and_unknown_parts_never_change(self):
        for fmt,name in [('docx','simple-run.docx'),('pptx','simple-shape.pptx')]:
            for mode in ('other','unknown','drop'):
                source=subset_samples()[name];out=runtime.simulate_for_tests(source,text_request(source,fmt),FakeTextExecutor(mode))
                self.assertEqual('simulation_failed',out['status'],out)
                self.assertEqual('fail',out['validation']['status'])
    def test_docx_complexity_and_locator_conflicts_block_dispatch(self):
        base=subset_samples()['simple-run.docx']
        cases=[build_complex_samples()['complex.docx'],rewrite(base,'word/document.xml',lambda b:b.replace(b'<sectPr/>',b'<sectPr><cols num="2"/></sectPr>')),
               rewrite(base,'word/document.xml',lambda b:b.replace(b'<r><rPr>',b'<r><fldChar/><rPr>'))]
        for source in cases:
            f=FakeTextExecutor();out=runtime.simulate_for_tests(source,text_request(source,'docx'),f)
            self.assertEqual('rejected',out['status'],out);self.assertFalse(f.calls)
        req=text_request(base,'docx');req['operation']['run_index']=0
        f=FakeTextExecutor();out=runtime.simulate_for_tests(base,req,f)
        self.assertEqual('rejected',out['status']);self.assertFalse(f.calls)
    def test_pptx_complexity_and_shape_identity_conflicts_block_dispatch(self):
        base=subset_samples()['simple-shape.pptx'];part='ppt/slides/slide1.xml'
        cases=[rewrite(base,part,lambda b:b.replace(b'<p:spPr>',b'<p:spPr><a:xfrm rot="60000"/>')),
               rewrite(base,part,lambda b:b.replace(b'<a:bodyPr/>',b'<a:bodyPr vert="vert"/>')),
               rewrite(base,part,lambda b:b.replace(b'</p:sld>',b'<p:timing/></p:sld>')),
               rewrite(base,part,lambda b:b.replace(b'name="Original title"',b'name="Original title" hidden="1"'))]
        for source in cases:
            f=FakeTextExecutor();out=runtime.simulate_for_tests(source,text_request(source,'pptx'),f)
            self.assertEqual('rejected',out['status'],out);self.assertFalse(f.calls)
        r=text_request(base,'pptx');r['operation']['shape_id']=3
        f=FakeTextExecutor();out=runtime.simulate_for_tests(base,r,f)
        self.assertEqual('rejected',out['status']);self.assertFalse(f.calls)
    def test_workers_do_not_import_third_party_engines(self):
        import sys
        from tools.document_fidelity.adapters import docx_worker,pptx_worker
        for worker in (docx_worker,pptx_worker):
            with self.assertRaises(RuntimeError):worker.edit_copy(None,None,None)
        self.assertNotIn('docx',sys.modules);self.assertNotIn('pptx',sys.modules)

class ExtraBoundaryTests(unittest.TestCase):
    def test_preview_invalid_dimensions_and_formula_is_unsupported(self):
        base=build_complex_samples()['complex.xlsx']
        for width in ('NaN','inf','garbage'):
            source=rewrite(base,'xl/worksheets/sheet1.xml',lambda b:b.replace(b'<sheetData>',f'<cols><col min="1" max="1" width="{width}"/></cols><sheetData>'.encode()))
            self.assertEqual('unsupported',xlsx.preview(source,request(source))['status'])
        req=request(base);req['operation'].update(cell='B1',expected='999')
        self.assertEqual('unsupported',xlsx.preview(base,req)['status'])
    def test_zero_default_row_height_is_hidden_and_rejected(self):
        base=build_complex_samples()['complex.xlsx']
        source=rewrite(base,'xl/worksheets/sheet1.xml',lambda b:b.replace(b'<sheetData>',b'<sheetFormatPr defaultRowHeight="0"/><sheetData>'))
        p=xlsx.preview(source,request(source));self.assertEqual('unsupported',p['status']);self.assertTrue(p['hidden']['row'])
        f=FakeExecutor();self.assertEqual('rejected',runtime.simulate_for_tests(source,request(source),f)['status']);self.assertFalse(f.calls)

    def test_missing_shape_identity_and_duplicate_ids_are_unsupported(self):
        base=subset_samples()['simple-shape.pptx'];part='ppt/slides/slide1.xml'
        for fn in (lambda b:b.replace(b'<p:cNvPr id="2" name="Original title"/>',b''),lambda b:b.replace(b'id="1" name=""',b'id="2" name=""')):
            source=rewrite(base,part,fn);f=FakeTextExecutor()
            out=runtime.simulate_for_tests(source,text_request(source,'pptx'),f)
            self.assertEqual('rejected',out['status']);self.assertFalse(f.calls)
    def test_wrong_slide_rels_and_wrong_local_hash_reject(self):
        base=subset_samples()['simple-shape.pptx']
        source=rewrite(base,'ppt/_rels/presentation.xml.rels',lambda b:b.replace(b'/slide"',b'/slideLayout"'))
        f=FakeTextExecutor();self.assertEqual('rejected',runtime.simulate_for_tests(source,text_request(source,'pptx'),f)['status']);self.assertFalse(f.calls)
        for fmt,name in [('docx','simple-run.docx'),('pptx','simple-shape.pptx')]:
            source=subset_samples()[name];r=text_request(source,fmt);r['operation']['target_sha256']='0'*64
            f=FakeTextExecutor();self.assertEqual('rejected',runtime.simulate_for_tests(source,r,f)['status']);self.assertFalse(f.calls)
    def test_docx_duplicate_text_field_and_whitespace_inputs_unsupported(self):
        base=subset_samples()['simple-run.docx']
        for fn in (lambda b:b.replace(b'<t>target</t>',b'<t>target</t><t>target</t>'),lambda b:b.replace(b'<r><rPr>',b'<r><fldChar/><rPr>')):
            source=rewrite(base,'word/document.xml',fn);f=FakeTextExecutor()
            self.assertEqual('rejected',runtime.simulate_for_tests(source,text_request(source,'docx'),f)['status']);self.assertFalse(f.calls)
        for text in (' needs space','new\nline','new\ttab'):
            r=text_request(base,'docx');r['operation']['replacement']=text;f=FakeTextExecutor()
            self.assertEqual('rejected',runtime.simulate_for_tests(base,r,f)['status']);self.assertFalse(f.calls)

class ReviewRegressionTests(unittest.TestCase):
    def test_ambiguous_xlsx_visibility_declarations_never_dispatch(self):
        base=build_complex_samples()['complex.xlsx']
        variants=[lambda b:b.replace(b'<sheetData>',b'<sheetFormatPr defaultRowHeight="15"/><sheetFormatPr defaultRowHeight="0"/><sheetData>'),
                  lambda b:b.replace(b'</sheetData>',b'<row r="1" hidden="1"><c r="D1"><v>7</v></c></row></sheetData>')]
        for transform in variants:
            with self.subTest(transform=transform):
                source=rewrite(base,'xl/worksheets/sheet1.xml',transform);r=request(source);f=FakeExecutor()
                self.assertEqual('unsupported',runtime.preview_target(source,r)['status'])
                self.assertEqual('rejected',runtime.simulate_for_tests(source,r,f)['status']);self.assertFalse(f.calls)
    def test_non_target_docx_text_is_always_leaf(self):
        base=subset_samples()['simple-run.docx']
        source=rewrite(base,'word/document.xml',lambda b:b.replace(b'Original </t>',b'Original <b/></t>'))
        r=text_request(source,'docx');f=FakeTextExecutor()
        self.assertEqual('unsupported',runtime.preview_target(source,r)['status'])
        self.assertEqual('rejected',runtime.simulate_for_tests(source,r,f)['status']);self.assertFalse(f.calls)
    def test_presentation_size_grammar_is_complete(self):
        base=subset_samples()['simple-shape.pptx']
        variants=[lambda b:b.replace(b'<sldSz cx="9144000" cy="6858000"/>',b'<sldSz cx="9144000" cy="6858000"><timing/></sldSz>'),
                  lambda b:b.replace(b'<sldSz ',b'<sldSz unknown="1" '),
                  lambda b:b.replace(b'<notesSz cx="6858000" cy="9144000"/>',b'<notesSz cx="6858000" cy="9144000"><timing/></notesSz>')]
        for transform in variants:
            with self.subTest(transform=transform):
                source=rewrite(base,'ppt/presentation.xml',transform);r=text_request(source,'pptx');f=FakeTextExecutor()
                self.assertEqual('unsupported',runtime.preview_target(source,r)['status'])
                self.assertEqual('rejected',runtime.simulate_for_tests(source,r,f)['status']);self.assertFalse(f.calls)

if __name__=='__main__':unittest.main()
