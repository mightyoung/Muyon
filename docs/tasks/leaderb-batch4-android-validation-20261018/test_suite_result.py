import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from suite_result import REQUIRED

class SubprocessAggregateTests(unittest.TestCase):
    def invoke(self,rows):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'rows.json';path.write_text(json.dumps(rows))
            result=subprocess.run([sys.executable,str(Path(__file__).with_name('suite_result.py')),str(path)],capture_output=True,text=True)
            return result.returncode,json.loads(result.stdout)
    def rows(self): return [dict(stage=name,exit=0) for name in sorted(REQUIRED)]
    def test_all_real_stage_results_green(self):
        code,verdict=self.invoke(self.rows());self.assertEqual(code,0);self.assertTrue(verdict['accepted'])
    def test_stage_exit_failure_rejected(self):
        rows=self.rows();rows[0]['exit']=7;code,verdict=self.invoke(rows);self.assertEqual(code,1);self.assertFalse(verdict['accepted'])
    def test_missing_inverse_rejected(self):
        rows=[r for r in self.rows() if r['stage']!='service-inverses'];code,verdict=self.invoke(rows);self.assertEqual(code,1);self.assertEqual(verdict['missing_stages'],['service-inverses'])
    def test_duplicate_cannot_fill_missing(self):
        rows=self.rows();rows.append(rows[0]);code,verdict=self.invoke(rows);self.assertEqual(code,1);self.assertFalse(verdict['accepted'])
if __name__=='__main__':unittest.main()
