import os
import json
from pathlib import Path
import unittest
from verify_shipping_records import load_record, verify_record

BASE = Path(os.environ['MUYON_SERVICE_BASELINE'])
SOURCE = '2fbdc13efd84cabf04623775f87e762cd0d08c11'

class Controls(unittest.TestCase):
    def setUp(self):
        self.row = (BASE / 'runs.tsv').read_text().splitlines()[0].split('\t')
        self.record = load_record(self.row)
    def test_original_jvm_records_have_valid_sibling(self):
        verify_record(self.row, self.record, SOURCE)
    def test_original_receipt_identity_cannot_be_substituted(self):
        self.record['native']['receipts'][0]['identity']['identity'] = '0' * 32
        with self.assertRaisesRegex(ValueError, 'original_receipt_identity'):
            verify_record(self.row, self.record, SOURCE)
    def test_raw_canary_cannot_enter_final_payload(self):
        self.record['outbound']['bytes'] += 'BORROWER_PRIVATE'
        with self.assertRaisesRegex(ValueError, 'canary_in_payload'):
            verify_record(self.row, self.record, SOURCE)
    def test_completed_task_must_have_exact_two_turn_budget(self):
        self.record['task']['calls'] = '3'
        with self.assertRaisesRegex(ValueError, 'task_identity_budget'):
            verify_record(self.row, self.record, SOURCE)
    def test_duplicate_durable_run_is_rejected(self):
        self.record['index']['runs'] *= 2
        with self.assertRaisesRegex(ValueError, 'one_durable_run'):
            verify_record(self.row, self.record, SOURCE)
    def test_receipt_ref_must_copy_original_bytes(self):
        body = json.loads(self.record['outbound']['bytes'])
        tool = next(v for v in body['messages'] if v['role'] == 'tool')
        projected = json.loads(tool['content'])
        projected['receipt_ref']['identity'] = '0' * 32
        tool['content'] = json.dumps(projected)
        self.record['outbound']['bytes'] = json.dumps(body)
        with self.assertRaisesRegex(ValueError, 'outbound_original_receipt'):
            verify_record(self.row, self.record, SOURCE)
    def test_second_payload_call_arguments_must_copy_admitted_binding(self):
        body = json.loads(self.record['outbound']['bytes'])
        body['messages'][1]['tool_calls'][0]['function']['arguments'] = '{"equipment_key":"wrong","include_loans":false}'
        self.record['outbound']['bytes'] = json.dumps(body)
        with self.assertRaisesRegex(ValueError, 'second_payload_original_call'):
            verify_record(self.row, self.record, SOURCE)
if __name__ == '__main__': unittest.main()
