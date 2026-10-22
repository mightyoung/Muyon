"""Fake executors only: never import/start openpyxl or any third-party engine."""
import hashlib
import io
import json
from pathlib import Path
import sys
import unittest
import zipfile
import xml.etree.ElementTree as ET

from tools.document_fidelity.complex_fixtures import build_complex_samples
from tools.document_fidelity.adapters import runtime

S='http://schemas.openxmlformats.org/spreadsheetml/2006/main'


def request(data):
    return dict(schema_version=1,scope_id='scope1',file_id='file1',base_revision='rev1',
                operation_id='op1',idempotency_key='key1',source_sha256=hashlib.sha256(data).hexdigest(),
                operation=dict(kind='set_numeric_cell',sheet='Original',cell='A1',expected='2',replacement='5'))


def edit_bytes(data, mode='ok'):
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        parts={name:z.read(name) for name in z.namelist()}
    parser=ET.XMLParser(target=ET.TreeBuilder(insert_comments=True,insert_pis=True))
    root=ET.fromstring(parts['xl/worksheets/sheet1.xml'],parser=parser)
    cells={c.get('r'):c for c in root.findall(f'.//{{{S}}}c')}
    cells['A1'].find(f'{{{S}}}v').text='5'
    if mode=='cache':cells['B1'].find(f'{{{S}}}v').text='6'
    if mode=='wrong_cell':cells['C1'].find(f'{{{S}}}v').text='9'
    if mode=='noop':cells['A1'].find(f'{{{S}}}v').text='2'
    parts['xl/worksheets/sheet1.xml']=ET.tostring(root)
    if mode=='drop':del parts['custom/original.bin']
    if mode=='unknown':parts['custom/original.bin']=b'changed'
    if mode=='add':parts['custom/new.bin']=b'added'
    out=io.BytesIO()
    with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
        for name,payload in parts.items():z.writestr(name,payload)
    return out.getvalue()

class FakeExecutor:
    """Local test double. Its products are not real engine round-trips."""
    kind='fake_executor'
    def __init__(self,mode='ok'):
        self.mode=mode;self.calls=[]
    def execute(self,launch,input_path,output_path,job_path):
        self.calls.append(launch)
        self.asserted_job=json.loads(job_path.read_text())
        self.input_mode=input_path.stat().st_mode & 0o777
        self.distinct_paths=input_path != output_path
        data=input_path.read_bytes()
        if self.mode=='exception':raise RuntimeError('fake executor failure')
        if self.mode=='unexpected_exception':raise TypeError('fake malformed response')
        if self.mode=='job_changed':
            job_path.chmod(0o600);job_path.write_text('{}')
        if self.mode=='timeout':return dict(status='timeout',exit_code=None,elapsed_ms=30001,stdout=b'',stderr=b'')
        if self.mode=='exit':return dict(status='exited',exit_code=1,elapsed_ms=1,stdout=b'',stderr=b'fake error')
        if self.mode=='missing':return dict(status='exited',exit_code=0,elapsed_ms=1,stdout=b'',stderr=b'')
        if self.mode=='symlink':output_path.symlink_to(input_path)
        elif self.mode=='oversize':output_path.write_bytes(b'0'*(8*1024*1024+1))
        else:output_path.write_bytes(edit_bytes(data,self.mode))
        if self.mode=='source_changed':
            input_path.chmod(0o600);input_path.write_bytes(b'fake source corruption')
        if self.mode=='extra_file':(output_path.parent/'unexpected.bin').write_bytes(b'extra')
        return dict(status='exited',exit_code=0,elapsed_ms=float('nan') if self.mode=='nan_time' else 1,
                    stdout=b'x'*32769 if self.mode=='stdout' else b'',stderr=b'')

class AdapterTests(unittest.TestCase):
    def setUp(self):self.source=build_complex_samples()['complex.xlsx'];self.req=request(self.source)
    def simulate(self,mode='ok',req=None):
        fake=FakeExecutor(mode)
        return runtime.simulate_for_tests(self.source,req or self.req,fake),fake
    def test_real_runtime_is_always_held_even_forged_pass_flags(self):
        r=runtime.run_real(self.source,self.req,admission={k:'pass' for k in ['license','provenance','isolation','resources']})
        self.assertEqual('held',r['status']);self.assertEqual('not_run',r['engine_execution'])
        self.assertIn('environment_hold',r['reasons'])
        self.assertNotIn('openpyxl',sys.modules)
    def test_fixed_launch_and_readonly_distinct_copy_and_simulation_labels(self):
        r,f=self.simulate()
        self.assertEqual('simulated_validated',r['status'],r)
        self.assertTrue(r['fake_executor_used']);self.assertEqual('not_run',r['real_roundtrip'])
        self.assertEqual('not_run',r['engine_execution']);self.assertEqual('unknown',r['fidelity'])
        self.assertEqual(0,f.input_mode & 0o222);self.assertTrue(f.distinct_paths)
        self.assertEqual(['/runtime/python3','-I','/adapter/openpyxl_worker.py','--request','/job/request.json'],f.calls[0]['argv'])
        self.assertEqual(30000,f.calls[0]['limits']['timeout_ms'])
        self.assertFalse(f.calls[0]['network']);self.assertTrue(f.calls[0]['input_read_only'])
        self.assertEqual(self.req,f.asserted_job)
        self.assertEqual(hashlib.sha256(self.source).hexdigest(),r['source_sha256'])
        self.assertEqual('pass',r['validation']['status'])
        for dim in ['render','recalc','visual','annotation']:self.assertEqual('not_run',r['dimensions'][dim])
    def test_missing_admission_is_hold(self):
        r=runtime.run_real(self.source,self.req)
        self.assertEqual('held',r['status']);self.assertIn('admission_missing',r['reasons'])
    def test_bad_hash_precondition_and_unknown_request_field_never_dispatch(self):
        for change in ['hash','expected','extra','formula','badcell']:
            req=json.loads(json.dumps(self.req))
            if change=='hash':req['source_sha256']='0'*64
            if change=='expected':req['operation']['expected']='3'
            if change=='extra':req['command']='touch /tmp/no'
            if change=='formula':req['operation']['replacement']='=WEBSERVICE("x")'
            if change=='badcell':req['operation']['cell']='XFE1'
            with self.subTest(change=change):
                r,f=self.simulate(req=req);self.assertEqual('rejected',r['status'],r);self.assertFalse(f.calls)
    def test_unknown_loss_rewrite_and_added_parts_fail(self):
        for mode in ['drop','unknown','add']:
            with self.subTest(mode=mode):
                r,_=self.simulate(mode);self.assertEqual('simulation_failed',r['status'],r)
                self.assertEqual('fail',r['validation']['status'])
    def test_cache_other_cell_and_noop_fail(self):
        for mode in ['cache','wrong_cell','noop']:
            with self.subTest(mode=mode):
                r,_=self.simulate(mode);self.assertEqual('simulation_failed',r['status'],r)
                self.assertEqual('fail',r['validation']['status'])
    def test_executor_timeout_exit_missing_oversize_logs_symlink_source_and_sidefile_fail(self):
        for mode in ['timeout','exit','missing','oversize','stdout','symlink','source_changed','extra_file','exception','unexpected_exception','job_changed','nan_time']:
            with self.subTest(mode=mode):
                r,_=self.simulate(mode);self.assertEqual('simulation_failed',r['status'],r)
        self.assertEqual(self.source,build_complex_samples()['complex.xlsx'])
    def test_formula_merged_and_hidden_targets_reject(self):
        for sheet,cell,expected in [('Original','B1','999'),('Original','A3','2'),('Hidden','A1','2')]:
            req=json.loads(json.dumps(self.req));req['operation'].update(sheet=sheet,cell=cell,expected=expected)
            r,f=self.simulate(req=req);self.assertEqual('rejected',r['status'],r);self.assertFalse(f.calls)
    def test_disabled_worker_entry_does_not_import_engine(self):
        from tools.document_fidelity.adapters import openpyxl_worker
        with self.assertRaises(RuntimeError):openpyxl_worker.edit_copy(None,None,None)
        self.assertNotIn('openpyxl',sys.modules)

if __name__=='__main__':unittest.main()
