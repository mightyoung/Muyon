import os
from pathlib import Path
import unittest
from cpu_reference import evaluate

class CpuReferenceTests(unittest.TestCase):
    def test_real_det_rec_on_synthetic_english_chinese_and_blank(self):
        report=evaluate(Path(os.environ['OCR_ASSETS']))
        self.assertEqual(report['runtime'],'1.21.1')
        self.assertEqual(report['provider'],'CPUExecutionProvider')
        for size in ['tiny','small']:
            pages=report['models'][size]
            self.assertIn('Total 123.45',' '.join(pages['english']['text']))
            self.assertIn('材料采购',''.join(pages['chinese']['text']))
            self.assertEqual(pages['blank']['text'],[])
            for page in pages.values():
                self.assertTrue(page['deterministic'])
                for box in page['boxes']:
                    self.assertEqual(len(box),4)
                    self.assertTrue(all(0<=x<=900 and 0<=y<=220 for x,y in box))

if __name__=='__main__': unittest.main()
