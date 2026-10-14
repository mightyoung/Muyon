import copy
from pathlib import Path
import sys
import tempfile
import unittest

HERE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(HERE))
from run_experiment import invoke_case

class InputIsolation(unittest.TestCase):
    def test_dut_receives_only_inputs_not_expected_or_id(self):
        fixture={'case_id':'secret-selector','input':{'initial_test_facts':{},'stimuli':[]},'expected':{'return_this':'not_allowed'},'source_refs':['oracle-ref']}
        captured=[]
        def engine(value,path):captured.append(value);return {'observations':{}}
        invoke_case(fixture,'unused',engine)
        self.assertEqual(captured,[fixture['input']])

    def test_changing_oracle_and_id_cannot_change_dut_input(self):
        a={'case_id':'A','input':{'initial_test_facts':{'active_cursor':{'store_id':'A','scope_id':'S','stream_id':'X','seq':'1'}},'stimuli':[]},'expected':{'required_observations':{'x':1}}}
        b=copy.deepcopy(a);b['case_id']='B';b['expected']={'required_observations':{'x':999}}
        def engine(value,path):return value
        self.assertEqual(invoke_case(a,'unused',engine),invoke_case(b,'unused',engine))

if __name__=='__main__':unittest.main()
