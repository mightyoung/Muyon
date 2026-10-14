import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
from seam import reduce, atomic_boundary, read_boundary


def cursor(seq, **changes):
    c = dict(store_id='lab-A', scope_id='lab-S', stream_id='lab-X', seq=str(seq))
    c.update(changes)
    return c


def run(facts, *actions):
    with tempfile.TemporaryDirectory() as tmp:
        return reduce({'initial_test_facts': facts, 'stimuli': list(actions)}, str(Path(tmp)/'lab.sqlite'))


def event(seq, **changes):
    return dict(test_action='receive_authorized_projection_event', cursor=cursor(seq, **changes), event_ref='lab-event-'+str(seq))


class RecoveryBehavior(unittest.TestCase):
    def test_domain_rejects_larger_seq_from_each_wrong_identity(self):
        for axis in ('store_id', 'scope_id', 'stream_id'):
            for sequence in [11,999]:
                r = run({'active_cursor': cursor(10)}, event(sequence, **{axis:'other'}))
                self.assertEqual(r['observations'].get('applied_cursor'), cursor(10))
                self.assertEqual(r['observations'].get('event_applications'), 0)

    def test_restart_from_durable_watermark_never_skips_volatile_applied_event(self):
        r=run({'active_cursor':cursor(11),'durable_cursor':cursor(10),'durable_state_ref':'lab-state-10'},event(12))
        self.assertEqual(r['observations'].get('durable_cursor'),cursor(10))
        self.assertEqual(r['observations'].get('applied_cursor'),cursor(10))
        self.assertEqual(r['observations'].get('incremental_apply'),'paused')
        self.assertEqual(r['persistent_boundary'],{'state_ref':'lab-state-10','cursor':cursor(10)})

    def test_existing_lab_checkpoint_wins_over_stale_or_volatile_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            db=str(Path(tmp)/'lab.sqlite')
            first=reduce({'initial_test_facts':{'active_cursor':cursor(10)},'stimuli':[event(11)]},db)
            self.assertEqual(first['persistent_boundary']['cursor'],cursor(11))
            resumed=reduce({'initial_test_facts':{'active_cursor':cursor(50)},'stimuli':[event(12)]},db)
            self.assertEqual(resumed['persistent_boundary']['cursor'],cursor(12))
            self.assertEqual(resumed['observations']['event_applications'],1)

    def test_contiguous_event_advances_once(self):
        r=run({'active_cursor':cursor(10)},event(11),event(11))
        self.assertEqual(r['observations'].get('applied_cursor'),cursor(11))
        self.assertEqual(r['observations'].get('event_applications'),1)

    def test_gap_pauses_bounded_incremental(self):
        r=run({'active_cursor':cursor(10)},event(12))
        self.assertEqual(r['observations'].get('durable_cursor'),cursor(10))
        self.assertEqual(r['observations'].get('incremental_apply'),'paused')

    def test_conflicting_duplicate_does_not_replace_payload(self):
        a=event(11);a['payload_ref']='payload-A'
        b=event(11);b['payload_ref']='payload-B'
        r=run({'active_cursor':cursor(10)},a,b)
        self.assertEqual(r['observations'].get('result'),'isolate_and_reconcile')
        self.assertEqual(r['observations'].get('event_applications'),1)

    def test_snapshot_commits_state_with_watermark_and_keeps_draft(self):
        with tempfile.TemporaryDirectory() as tmp:
            db=str(Path(tmp)/'lab.sqlite')
            r=reduce({'initial_test_facts':{'active_cursor':cursor(8),'independent_draft_ref':'draft-r2'},'stimuli':[dict(test_action='install_snapshot_candidate',domain=cursor(10),covered_through_seq='10',state_ref='lab-state-10',integrity='valid',authority_ref='auth-current',schema_ref='synthetic-compatible')]},db)
            self.assertEqual(read_boundary(db),{'state_ref':'lab-state-10','cursor':cursor(10)})
            self.assertEqual(r['observations'].get('draft_ref'),'draft-r2')

    def test_late_snapshot_does_not_replace_new_state(self):
        r=run({'active_cursor':cursor(11)},dict(test_action='late_snapshot_candidate',cursor=cursor(8)))
        self.assertEqual(r['observations'].get('applied_cursor'),cursor(11))
        self.assertEqual(r['observations'].get('candidate_activations'),0)

    def test_old_epoch_display_rejected_but_ledger_lookup_preserves_effect(self):
        r=run({'active_cursor':cursor(10),'process_epoch':'E2','operation_ref':'op'},dict(test_action='old_display_callback',epoch='E1'),dict(test_action='old_receipt_hint',epoch='E1',operation_ref='op',intent_ref='intent',attempt_ref='attempt',payload_digest_ref='digest',source_ref='synthetic-core-ledger'),dict(test_action='current_connection_readonly_receipt_lookup',epoch='E2',matching_identity_and_digest=True,authoritative_outcome='succeeded'))
        self.assertEqual(r['observations'].get('old_display_updates'),0)
        self.assertEqual(r['observations'].get('original_effect'),'succeeded')
        self.assertNotIn('receipt_ref',r['observations']) # no supplied receipt ID

    def test_hint_without_authoritative_lookup_cannot_claim_success(self):
        r=run({'active_cursor':cursor(10),'process_epoch':'E2'},dict(test_action='old_receipt_hint',epoch='E1',operation_ref='op'))
        self.assertNotIn('original_effect',r['observations'])

    def test_unknown_stays_unknown_and_never_replays(self):
        r=run({'active_cursor':cursor(10),'mode_label':'FullAllow'},dict(test_action='recover_operation',evidence_label='lookup_not_found',zero_dispatch_proof=False),dict(test_action='reconcile_original',reliable_effect_evidence=False))
        self.assertEqual(r['observations'].get('effect_outcome_label'),'outcome_unknown')
        self.assertEqual(r['observations'].get('automatic_dispatches'),0)
        self.assertEqual(r['observations'].get('additional_pure_risk_confirmations'),0)

    def test_new_effect_does_not_resolve_old_unknown(self):
        bindings={k:'lab-'+k for k in ['user_instruction_ref','original_unknown_action_ref','original_record_version_ref','display_revision_ref','scope_ref','action_type_ref','normalized_target_ref','normalized_parameter_digest_ref','new_intent_ref','new_plan_digest_ref']}
        r=run({'active_cursor':cursor(10),'mode_label':'FullAllow','old_outcome':'outcome_unknown','all_hard_prerequisites_valid':True},dict(test_action='trusted_explicit_user_do_again',bindings=bindings,host_link_ref='lab-link',trusted_issuer_fixture=True),dict(test_action='new_operation_succeeds',new_receipt_ref='lab-new-receipt'))
        self.assertEqual(r['observations'].get('old_outcome'),'outcome_unknown')
        self.assertEqual(r['observations'].get('new_outcome'),'succeeded')
        self.assertEqual(r['observations'].get('new_receipt_ref'),'lab-new-receipt')

    def test_fake_instruction_cannot_dispatch(self):
        r=run({'active_cursor':cursor(10),'old_outcome':'outcome_unknown'},dict(test_action='claim_do_again',origin='model_retry',authentic_user_instruction_evidence=False))
        self.assertEqual(r['observations'].get('new_business_dispatches'),0)
        self.assertEqual(r['observations'].get('host_link_issued'),False)

    def test_delivery_unknown_retains_original_identity(self):
        facts={'active_cursor':cursor(10),'pending_identity':{'client_message_ref':'m','submission_intent_ref':'i','draft_revision':'r'}}
        r=run(facts,dict(test_action='submission_timeout'),dict(test_action='query_original_acceptance_identity',trusted_result='no_evidence'),dict(test_action='duplicate_ipc_delivery'))
        self.assertEqual(r['observations'].get('delivery_state_label'),'delivery_unknown')
        self.assertEqual(r['observations'].get('submission_intent_ref'),'i')
        self.assertEqual(r['observations'].get('additional_duplicate_confirmed_messages'),0)

    def test_unpermitted_body_not_persisted_across_restart(self):
        r=run({'active_cursor':cursor(10),'pending_input':{'client_message_ref':'m','submission_intent_ref':'i','body_placeholder_ref':'placeholder'},'effective_policy':{'draft_body_persistence_permitted':False,'minimal_non_body_identity_audit_permitted':True}},dict(test_action='compression_and_snapshot_replace_projection'),dict(test_action='process_exit_then_restart'))
        self.assertEqual(r['observations'].get('body_recovery_promised'),False)
        self.assertEqual(r['observations'].get('nonrecoverable_body_notice_required'),True)
        self.assertEqual(r['observations'].get('pending_identity_preserved'),True)

    def test_buffer_pressure_resync_without_dropping_fact(self):
        r=run({'active_cursor':cursor(10),'test_buffer_limit':{'event_count':2,'bytes':64,'product_default':False}},dict(test_action='slow_subscription_receives',event_count=3,total_bytes=96),dict(test_action='coincident_facts',refs=['terminal','receipt'],progress_ref='ephemeral'))
        self.assertLessEqual(r['observations'].get('buffer_peak_events_max',999),2)
        self.assertEqual(r['observations'].get('subscription_action_one_of'),'pause')
        self.assertEqual(r['observations'].get('authoritative_facts_persisted_first'),True)

    def test_fullallow_risk_separate_from_hard_cas_limit(self):
        r=run({'active_cursor':cursor(10),'mode_label':'FullAllow','high_risk_label':True,'all_scope_purpose_capability_business_cas_valid':True},dict(test_action='evaluate_current_new_intent_plan'),dict(test_action='hard_prerequisite_fails',reason='cas_conflict'))
        self.assertEqual(r['observations'].get('additional_pure_risk_confirmations'),0)
        self.assertEqual(r['observations'].get('business_writes'),0)
        self.assertEqual(r['observations'].get('result'),'reject_or_replan_with_true_reason')

    def test_verified_projection_advance_does_not_expose_audit_counts(self):
        r=run({'active_cursor':cursor(10)},dict(test_action='receive_authorized_projection_advance',from_cursor=cursor(10),next_cursor=cursor(13),evidence_ref='injected-core-evidence',evidence_valid=True))
        self.assertEqual(r['observations'].get('applied_cursor'),cursor(13))
        self.assertEqual(r['observations'].get('audit_counter_exposed'),False)
        self.assertNotIn('hidden_event_count',r['observations'])
        bad=run({'active_cursor':cursor(10)},dict(test_action='receive_authorized_projection_advance',from_cursor=cursor(10),next_cursor=cursor(13),evidence_ref='invalid',evidence_valid=False))
        self.assertEqual(bad['observations'].get('applied_cursor'),cursor(10))

    def test_permission_narrowing_clears_before_snapshot_request(self):
        r=run({'active_cursor':cursor(10)},dict(test_action='trusted_read_permission_narrows',new_authority_ref='narrow'),dict(test_action='receive_old_permission_projection',cursor=cursor(11)),dict(test_action='request_current_permission_snapshot',new_stream='new'))
        self.assertEqual(r['observations'].get('operation_order'),['clear_affected_projection','request_current_permission_snapshot'])
        self.assertEqual(r['observations'].get('old_projection_applications'),0)

    def test_repair_failure_does_not_erase_known_receipt(self):
        r=run({'active_cursor':cursor(10),'known_receipt_ref':'known-success'},dict(test_action='repair_attempt',fault='snapshot_digest_mismatch'))
        self.assertEqual(r['observations'].get('known_receipt_ref'),'known-success')
        self.assertEqual(r['observations'].get('invalid_snapshot_activations'),0)
        self.assertIn(r['observations'].get('history_completeness_one_of'),['partial','unavailable'])


class PhysicalSQLiteBoundary(unittest.TestCase):
    def test_process_exit_between_state_and_cursor_rolls_back(self):
        self.assert_crash_boundary('after_state_write',{'state_ref':'old','cursor':cursor(10)})

    def test_process_exit_after_commit_retains_pair(self):
        self.assert_crash_boundary('after_commit',{'state_ref':'new','cursor':cursor(11)})

    def assert_crash_boundary(self,fault,wanted):
        with tempfile.TemporaryDirectory() as tmp:
            db=str(Path(tmp)/'lab.sqlite')
            atomic_boundary(db,'old',cursor(10))
            code='import sys;sys.path.insert(0,sys.argv[1]);from seam import atomic_boundary;import json;atomic_boundary(sys.argv[2],"new",json.loads(sys.argv[3]),sys.argv[4])'
            result=subprocess.run([sys.executable,'-c',code,str(HERE),db,json.dumps(cursor(11)),fault],capture_output=True)
            self.assertEqual(read_boundary(db),wanted)
            self.assertEqual(result.returncode,77)

if __name__=='__main__':unittest.main()
