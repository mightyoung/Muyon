"""Contract oracle tests only: no Service, provider, store or tool execution."""
import copy
import unittest
from contract import ProjectionState, validate_submission


def submission():
    return dict(protocol=1, epoch='epoch-1', lease='lease-1', request_id='req-1',
                text='读取供应商名称', selected=dict(module_id='inquiry', type='supplier',
                key='sup-1', revision='7', schema_version=1))


def event(cursor, kind, **payload):
    return dict(epoch='epoch-1', request_id='req-1', run_id='run-1', cursor=cursor,
                kind=kind, payload=payload)


class SubmissionTests(unittest.TestCase):
    def test_typed_bounded_submission(self):
        self.assertTrue(validate_submission(submission()))

    def test_missing_wrong_type_and_overflow_rejected(self):
        for key, value in [('protocol', True), ('epoch', ''), ('lease', ''),
                           ('request_id', 4), ('text', '中' * 1366), ('text', '  \t\n')]:
            item = submission(); item[key] = value
            self.assertFalse(validate_submission(item), key)
        item = submission(); del item['lease']
        self.assertFalse(validate_submission(item))

    def test_authority_and_transport_fields_never_accepted(self):
        for key in ['path', 'sql', 'grant', 'credentials', 'approved', 'endpoint']:
            item = submission(); item[key] = 'x'
            self.assertFalse(validate_submission(item), key)
            item = submission(); item['selected'][key] = 'x'
            self.assertFalse(validate_submission(item), key)

    def test_selected_supplier_only_and_no_path_like_identifiers(self):
        for key, value in [('module_id', 'equipment'), ('type', 'contact'),
                           ('key', '../source.db'), ('revision', 'x' * 129),
                           ('schema_version', True), ('schema_version', 12)]:
            item = submission(); item['selected'][key] = value
            self.assertFalse(validate_submission(item))


class EventTests(unittest.TestCase):
    def setUp(self):
        self.state = ProjectionState(submission(), 'run-1')

    def test_order_and_replay_are_deterministic(self):
        first = event(1, 'answer_delta', text='名称：')
        self.assertEqual(self.state.apply(first), 'applied')
        self.assertEqual(self.state.apply(first), 'duplicate')
        self.assertEqual(self.state.apply(event(3, 'answer_delta', text='gap')), 'gap')
        self.assertEqual(self.state.cursor, 1)
        self.assertEqual(self.state.answer, '名称：')
        changed = copy.deepcopy(first); changed['payload']['text'] = 'conflict'
        self.assertEqual(self.state.apply(changed), 'conflict')

    def test_wrong_identity_stale_lease_and_run_cannot_mutate(self):
        for key in ['epoch', 'request_id', 'run_id']:
            item = event(1, 'answer_delta', text='bad'); item[key] = 'other'
            self.assertEqual(self.state.apply(item), 'identity_mismatch')
        self.assertEqual(self.state.cancel('epoch-1', 'old-lease', 'req-1'), 'rejected')
        self.assertEqual(self.state.cursor, 0)

    def test_original_receipt_and_current_projection_separate(self):
        receipt = event(1, 'receipt', opaque_id='original-durable-42', outcome='recorded_success')
        self.assertEqual(self.state.apply(receipt), 'applied')
        self.assertEqual(self.state.apply(event(2, 'supplier_projection', key='sup-1',
                         revision='7', name='供应商甲', receipt_id='original-durable-42')), 'applied')
        self.assertEqual(self.state.projection['name'], '供应商甲')
        self.state.invalidate_projection()
        self.assertIsNone(self.state.projection)
        self.assertEqual(self.state.receipt['opaque_id'], 'original-durable-42')
        self.assertEqual(self.state.apply(event(3, 'receipt', opaque_id='fabricated',
                         outcome='recorded_success')), 'invalid')

    def test_projection_requires_matching_object_revision_and_original_receipt(self):
        self.state.apply(event(1, 'receipt', opaque_id='receipt-1', outcome='recorded_success'))
        for update in [dict(key='other'), dict(revision='8'), dict(receipt_id='other')]:
            data = dict(key='sup-1', revision='7', name='供应商甲', receipt_id='receipt-1')
            data.update(update)
            self.assertEqual(self.state.apply(event(2, 'supplier_projection', **data)), 'invalid')
        self.assertEqual(self.state.cursor, 1)
        self.assertIsNone(self.state.projection)

    def test_binder_loss_and_unknown_only_reconcile_never_resubmit(self):
        self.state.binder_lost()
        self.assertEqual(self.state.status, 'unknown')
        self.assertEqual(self.state.recovery_action(), ('lookup', 'req-1', 'run-1', 0))
        self.assertFalse(self.state.can_submit)
        self.assertEqual(self.state.apply(event(1, 'terminal', outcome='unknown')), 'applied')
        self.assertEqual(self.state.recovery_action()[0], 'lookup')
        self.assertFalse(self.state.can_submit)

    def test_reconnect_lookup_uses_new_lease_without_rewriting_admitted_epoch(self):
        self.state.binder_lost()
        self.state.reconnect('epoch-2', 'lease-2')
        self.assertEqual(self.state.connection, ('epoch-2', 'lease-2'))
        self.assertEqual(self.state.admitted_epoch, 'epoch-1')
        self.assertEqual(self.state.recovery_action(), ('lookup', 'req-1', 'run-1', 0))
        self.assertEqual(self.state.cancel('epoch-1', 'lease-1', 'req-1'), 'rejected')
        self.state.reauthorize_display()
        self.assertEqual(self.state.apply(event(1, 'answer_delta', text='replayed')), 'applied')
        self.assertFalse(self.state.can_submit)

    def test_cancel_is_request_not_fabricated_terminal(self):
        self.assertEqual(self.state.cancel('epoch-1', 'lease-1', 'req-1'), 'requested')
        self.assertEqual(self.state.status, 'cancel_requested')
        self.assertIsNone(self.state.terminal)
        self.assertEqual(self.state.apply(event(1, 'terminal', outcome='cancelled')), 'applied')
        self.assertEqual(self.state.terminal, 'cancelled')
        self.assertEqual(self.state.apply(event(2, 'answer_delta', text='late')), 'terminal')

    def test_completion_requires_durable_success_receipt(self):
        self.assertEqual(self.state.apply(event(1, 'terminal', outcome='completed')), 'invalid')
        self.assertEqual(self.state.apply(event(1, 'receipt', opaque_id='original',
                         outcome='recorded_success')), 'applied')
        self.assertEqual(self.state.apply(event(2, 'terminal', outcome='completed')), 'invalid')
        self.assertEqual(self.state.apply(event(2, 'supplier_projection', key='sup-1',
                         revision='7', name='Supplier', receipt_id='original')), 'applied')
        self.assertEqual(self.state.apply(event(3, 'terminal', outcome='completed')), 'applied')

    def test_opaque_receipt_is_utf8_not_identifier(self):
        opaque = 'durable:供应商/receipt#42'
        self.assertEqual(self.state.apply(event(1, 'receipt', opaque_id=opaque,
                         outcome='recorded_success')), 'applied')
        self.assertEqual(self.state.receipt['opaque_id'], opaque)
        other = ProjectionState(submission(), 'run-1')
        self.assertEqual(other.apply(event(1, 'receipt', opaque_id='中' * 85 + 'a',
                         outcome='recorded_success')), 'applied')
        for opaque in ['', '中' * 86, '\ud800']:
            other = ProjectionState(submission(), 'run-1')
            self.assertEqual(other.apply(event(1, 'receipt', opaque_id=opaque,
                             outcome='recorded_success')), 'invalid')

    def test_display_invalidation_clears_and_blocks_business_until_host_reauthorization(self):
        self.state.apply(event(1, 'answer_delta', text='private name'))
        self.state.apply(event(2, 'receipt', opaque_id='original', outcome='recorded_success'))
        self.state.invalidate_projection()
        self.assertEqual(self.state.answer, '')
        self.assertEqual(self.state.apply(event(3, 'answer_delta', text='still private')), 'display_not_authorized')
        self.assertEqual(self.state.apply(event(3, 'supplier_projection', key='sup-1',
                         revision='7', name='Supplier', receipt_id='original')), 'display_not_authorized')
        self.state.reconnect('epoch-2', 'lease-2')
        self.assertEqual(self.state.apply(event(3, 'answer_delta', text='still private')), 'display_not_authorized')
        self.assertEqual(self.state.receipt['opaque_id'], 'original')
        self.state.reauthorize_display()
        self.assertEqual(self.state.apply(event(3, 'answer_delta', text='authorized')), 'applied')

    def test_binder_loss_clears_answer_and_still_accepts_receipt_metadata(self):
        self.state.apply(event(1, 'answer_delta', text='private'))
        self.state.binder_lost()
        self.assertEqual(self.state.answer, '')
        self.assertEqual(self.state.apply(event(2, 'receipt', opaque_id='original',
                         outcome='recorded_success')), 'applied')
        self.assertEqual(self.state.apply(event(3, 'answer_delta', text='private')), 'display_not_authorized')

    def test_answer_delta_byte_limit_is_1024(self):
        self.assertEqual(self.state.apply(event(1, 'answer_delta', text='a' * 1024)), 'applied')
        self.assertEqual(self.state.apply(event(2, 'answer_delta', text='a' * 1025)), 'invalid')
        self.assertEqual(self.state.apply(event(2, 'answer_delta', text='中' * 342)), 'invalid')
        self.assertEqual(self.state.cursor, 1)

    def test_object_schema_version_required(self):
        item = submission(); del item['selected']['schema_version']
        self.assertFalse(validate_submission(item))

    def test_malformed_or_unbounded_events_atomic_rejection(self):
        for item in [event(True, 'answer_delta', text='x'), event(1, 'answer_delta', text='x' * 4097),
                     event(1, 'answer_delta', text='x', sql='select'), event(1, 'grant', approved=True)]:
            self.assertEqual(self.state.apply(item), 'invalid')
        self.assertEqual(self.state.cursor, 0)
        self.assertEqual(self.state.answer, '')


if __name__ == '__main__':
    unittest.main()
