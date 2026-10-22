import copy
import unittest
from same_source_shipping_inverses import metadata_matches, classify

class ContractTests(unittest.TestCase):
    def setUp(self):
        self.source='a'*40
        self.contract={'source_sha':self.source,'library_sha256':'b'*64,'probe_jar_sha256':'c'*64}
        self.linux={'classification':'GREEN','source_sha':self.source,'library_sha256':'b'*64,'source_inputs_unchanged':True}
        self.service=dict(self.linux,probe_sha256='c'*64)
    def ok(self):
        return metadata_matches(self.source,self.contract,self.linux,self.service)
    def test_same_run_sibling(self): self.assertTrue(self.ok())
    def test_cross_source_rejected(self):
        self.service['source_sha']='d'*40;self.assertFalse(self.ok())
    def test_cross_library_rejected(self):
        self.service['library_sha256']='d'*64;self.assertFalse(self.ok())
    def test_cross_probe_rejected(self):
        self.service['probe_sha256']='d'*64;self.assertFalse(self.ok())
    def test_invalid_producer_rejected(self):
        self.linux['classification']='INVALID';self.assertFalse(self.ok())
    def test_changed_inputs_rejected(self):
        self.service['source_inputs_unchanged']=False;self.assertFalse(self.ok())
    def test_unrelated_failure_is_not_killed(self):
        record={'exit_code':1,'timed_out':False,'forced_owned_group_cleanup':False,'live_after_cleanup':[]}
        self.assertFalse(classify('Exception in thread "main" java.lang.IllegalStateException: OTHER\n',record,'duplicate_is_existing'))
    def test_exact_mutant_assertion(self):
        record={'exit_code':1,'timed_out':False,'forced_owned_group_cleanup':False,'live_after_cleanup':[]}
        self.assertTrue(classify('Exception in thread "main" java.lang.IllegalStateException: SERVICE_SHIPPING_ASSERT:duplicate_is_existing\n',record,'duplicate_is_existing'))
    def test_timeout_is_not_killed(self):
        record={'exit_code':1,'timed_out':True,'forced_owned_group_cleanup':False,'live_after_cleanup':[]}
        self.assertFalse(classify('Exception in thread "main" java.lang.IllegalStateException: SERVICE_SHIPPING_ASSERT:duplicate_is_existing\n',record,'duplicate_is_existing'))

if __name__=='__main__': unittest.main()
