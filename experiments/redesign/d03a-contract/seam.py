"""Independent experimental reducer and isolated SQLite lab persistence.

Consumes only input facts and actions. No oracle, fixture IDs, product DTO or
production permission/receipt proof verifier is present in this module.
"""
import copy
import json
import os
import sqlite3


def connection(path):
    db=sqlite3.connect(path)
    db.execute('CREATE TABLE IF NOT EXISTS boundary (slot INTEGER PRIMARY KEY, state_ref TEXT, cursor_json TEXT)')
    db.execute('CREATE TABLE IF NOT EXISTS lab_facts (kind TEXT, ref TEXT, value_json TEXT, PRIMARY KEY(kind,ref))')
    db.commit()
    return db


def atomic_boundary(db_path,state_ref,cursor,fault=None):
    with connection(db_path) as db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('INSERT OR IGNORE INTO boundary VALUES (1,NULL,NULL)')
        db.execute('UPDATE boundary SET state_ref=? WHERE slot=1',(state_ref,))
        if fault=='after_state_write':os._exit(77)
        db.execute('UPDATE boundary SET cursor_json=? WHERE slot=1',(json.dumps(cursor,sort_keys=True),))
        db.commit()
        if fault=='after_commit':os._exit(77)


def read_boundary(db_path):
    with connection(db_path) as db:
        row=db.execute('SELECT state_ref,cursor_json FROM boundary WHERE slot=1').fetchone()
    return None if row is None else {'state_ref':row[0],'cursor':json.loads(row[1])}


def persist_fact(path,kind,ref,value):
    with connection(path) as db:
        db.execute('INSERT OR REPLACE INTO lab_facts VALUES (?,?,?)',(kind,ref,json.dumps(value,sort_keys=True)))


def read_fact(path,kind,ref):
    with connection(path) as db:
        row=db.execute('SELECT value_json FROM lab_facts WHERE kind=? AND ref=?',(kind,ref)).fetchone()
    return None if row is None else json.loads(row[0])


def domain(cursor):
    return tuple(cursor[k] for k in ('store_id','scope_id','stream_id'))


def valid_cursor(cursor):
    return (isinstance(cursor,dict) and set(cursor)=={'store_id','scope_id','stream_id','seq'} and
            all(isinstance(cursor[k],str) and cursor[k] for k in ('store_id','scope_id','stream_id')) and
            isinstance(cursor['seq'],str) and cursor['seq'].isascii() and cursor['seq'].isdigit())


def reduce(inputs,db_path):
    facts=copy.deepcopy(inputs['initial_test_facts'])
    active=copy.deepcopy(facts.get('active_cursor'))
    initial_gaps=[]
    def stop(reason):
        return {'observations':{},'gaps':[reason],'processed':0,
                'layer':'unsupported_initial_boundary','action_evidence':[],
                'observation_provenance':{},'persistent_boundary':None}
    if not valid_cursor(active):return stop('missing_complete_initial_cursor')
    checkpoint=read_boundary(db_path)
    if checkpoint is None:
        durable=copy.deepcopy(facts.get('durable_cursor',active))
        if not valid_cursor(durable) or domain(durable)!=domain(active):
            return stop('invalid_or_cross_domain_initial_durable_boundary')
        state_ref=facts.get('durable_state_ref',facts.get('state_ref','lab-initial-placeholder'))
        atomic_boundary(db_path,state_ref,durable)
        checkpoint=read_boundary(db_path)
    if not valid_cursor(checkpoint['cursor']) or domain(checkpoint['cursor'])!=domain(active):
        return stop('existing_checkpoint_domain_requires_explicit_bootstrap_M03')
    current=copy.deepcopy(checkpoint['cursor']);state_ref=checkpoint['state_ref']
    if active!=current:initial_gaps.append('volatile_active_cursor_ignored_resume_from_committed_lab_boundary')
    epoch=facts.get('process_epoch')
    o={'applied_cursor':copy.deepcopy(current),'durable_cursor':read_boundary(db_path)['cursor'],
       'event_applications':0,'cursor_advancements':0,'additional_notifications':0,'additional_applications':0,
       'display_updates':0,'old_display_updates':0,'receipt_deletions':0,
       'new_business_dispatches':0,'automatic_dispatches':0,'automatic_resends':0,
       'business_rollbacks':0,'authoritative_receipts_created':0,'effect_success_proven':False}
    gaps=initial_gaps;processed=0;seen={};buffer=[];hint=None;link=None;new_outcome=None;permission_narrowed=False;permission_steps=[];action_evidence=[]
    initial_observation_keys=set(o)
    if 'old_outcome' in facts:o['old_outcome']=facts['old_outcome']
    if 'current_fragment_ref' in facts:o['current_fragment_ref']=facts['current_fragment_ref']
    if 'draft_ref' in facts:o['draft_ref']=facts['draft_ref']
    if 'independent_draft_ref' in facts:o['draft_ref']=facts['independent_draft_ref']
    if facts.get('event_identity'):
        seen[facts['event_identity']]=facts.get('payload_ref')
    pending=copy.deepcopy(facts.get('pending_identity',facts.get('pending_input',{})))
    if pending:
        safe={k:v for k,v in pending.items() if k in ('client_message_ref','submission_intent_ref','draft_revision','delivery_state_label')}
        if facts.get('effective_policy',{}).get('minimal_non_body_identity_audit_permitted',True):
            persist_fact(db_path,'pending',safe.get('client_message_ref','lab-pending'),safe)
        o.update(safe)
    def fullallow_risk():
        if facts.get('mode_label')=='FullAllow':o['additional_pure_risk_confirmations']=0
        else:gaps.append('mode_rule_not_supplied_D01a_M03')
    def receive(a):
        nonlocal current,state_ref
        c=a['cursor']
        if not valid_cursor(c):gaps.append('invalid_cursor_test_input');return
        if domain(c)!=domain(current):
            o['larger_seq_overrides_domain']=False;return
        identity=a.get('event_ref',str(c['seq']));payload=a.get('payload_ref')
        if identity in seen and seen[identity]!=payload:
            o['result']='isolate_and_reconcile';o['silent_payload_overwrite']=False;return
        if int(c['seq'])<=int(current['seq']):return
        if int(c['seq'])!=int(current['seq'])+1:
            o.update(incremental_apply='paused',repair_from=copy.deepcopy(o['durable_cursor']),buffer='bounded')
            limit=facts.get('test_buffer_limit',{}).get('event_count',2)
            if len(buffer)<limit:buffer.append(copy.deepcopy(a))
            else:o['subscription_action_one_of']='pause'
            return
        seen[identity]=payload;current=copy.deepcopy(c)
        o['event_applications']+=1;o['cursor_advancements']+=1
        o['applied_cursor']=copy.deepcopy(current)
        # Concrete event payload/state absent in v1: persist cursor + symbolic
        # laboratory state only, never claim actual product projection content.
        state_ref=json.dumps({'previous_state_ref':state_ref,'applied_event_ref':identity,'payload_ref':payload},sort_keys=True)
        if payload is None:gaps.append('event_payload_absent_symbolic_timeline_only_M03')
        atomic_boundary(db_path,state_ref,current)
        o['durable_cursor']=read_boundary(db_path)['cursor']
        o['cross_domain_comparisons']=0
        o['business_reexecution']=False
    for a in inputs['stimuli']:
        kind=a.get('test_action');handled=True;processed+=1
        mechanism={
            'install_snapshot_candidate':'lab_sqlite_symbolic_snapshot_not_product_state',
            'late_snapshot_candidate':'watermark_guard_no_actual_snapshot_payload',
            'snapshot_candidate':'integrity_label_guard_no_actual_snapshot_parser',
            'restart_connection':'epoch_value_change_not_actual_process_restart',
            'slow_subscription_receives':'lab_budget_queue_synthetic_sizes_not_real_event_bytes',
            'coincident_facts':'lab_sqlite_metadata_refs_not_actual_terminal_receipts',
            'old_receipt_hint':'metadata_hint_not_authoritative_effect',
            'current_connection_readonly_receipt_lookup':'injected_lookup_response_no_actual_receipt_digest_verifier',
            'compression_and_snapshot_replace_projection':'no_actual_compression_snapshot_or_draft_transform',
            'process_exit_then_restart':'sqlite_connection_reopen_not_actual_process_restart_or_body_restore',
            'query_original_acceptance_identity':'injected_acceptance_fact_not_actual_message_submission',
            'duplicate_ipc_delivery':'policy_zero_default_no_actual_message_deduplication_store',
            'trusted_explicit_user_do_again':'lab_injected_link_no_production_signature_or_association_verifier',
            'new_operation_succeeds':'injected_success_ref_not_actual_new_business_execution',
            'evaluate_current_new_intent_plan':'aggregate_fixture_boolean_not_individual_hard_prerequisite_validation',
            'hard_prerequisite_fails':'policy_rejection_no_actual_command_executor',
            'trusted_cancel_received_before_commit':'injected_cancel_evidence_no_actual_executor_commit_race',
        }.get(kind,'input_driven_policy_or_symbolic_lab_decision_not_full_operation_execution')
        action_evidence.append({'test_action':kind,'mechanism':mechanism})
        gaps.append('experiment_layer_limit:'+mechanism)
        if kind in ('receive_authorized_projection_event','receive_projection_event','receive_event','redeliver_event'):
            receive(a)
        elif kind=='receive_event_without_advance_evidence':receive(a)
        elif kind=='buffer_events':buffer.extend(copy.deepcopy(a.get('events',[])))
        elif kind in ('install_snapshot_candidate','late_snapshot_candidate','snapshot_candidate'):
            c=a.get('domain',a.get('cursor'));o['candidate_activations']=0
            if not valid_cursor(c) or domain(c)!=domain(current):gaps.append('snapshot_domain_or_bootstrap_not_validated');continue
            if int(c['seq'])<int(current['seq']):o['arrival_time_orders_versions']=False;continue
            if a.get('digest_relation')=='different':o.update(next_operation='isolate_and_reconcile',same_seq_proves_same_state=False);continue
            if kind!='install_snapshot_candidate' or a.get('integrity')!='valid' or a.get('schema_ref')!='synthetic-compatible' or not a.get('state_ref'):
                gaps.append('missing_actual_snapshot_integrity_schema_state');continue
            if facts.get('authority_revision') and a.get('authority_ref')!=facts['authority_revision']:
                gaps.append('snapshot_authority_mismatch');continue
            if a.get('covered_through_seq')!=c['seq']:gaps.append('snapshot_watermark_mismatch');continue
            state_ref=a['state_ref'];atomic_boundary(db_path,state_ref,c)
            current=copy.deepcopy(c);o.update(applied_cursor=copy.deepcopy(c),durable_cursor=read_boundary(db_path)['cursor'],atomic_snapshot_durable_boundary=copy.deepcopy(c),candidate_activations=1,covered_buffer_events_reapplied=0)
            applied=[]
            for e in sorted(buffer,key=lambda e:int(e['cursor']['seq'])):
                if domain(e['cursor'])==domain(current) and int(e['cursor']['seq'])>int(current['seq']):
                    prior=o['event_applications'];receive(e)
                    if o['event_applications']>prior:applied.append(e['event_ref'])
            o.update(post_snapshot_events_applied=applied,final_applied_cursor=copy.deepcopy(current),draft_overwritten=False,snapshot_claims_executor_alive=False)
            buffer=[]
        elif kind=='receive_authorized_projection_advance':
            c=a.get('next_cursor');start=a.get('from_cursor')
            if a.get('evidence_valid') and a.get('evidence_ref') and valid_cursor(c) and start==current and domain(c)==domain(current) and int(c['seq'])>int(current['seq']):
                state_ref=json.dumps({'previous_state_ref':state_ref,'authorized_advance_ref':a['evidence_ref']},sort_keys=True)
                atomic_boundary(db_path,state_ref,c);current=copy.deepcopy(c)
                o.update(applied_cursor=copy.deepcopy(c),durable_cursor=read_boundary(db_path)['cursor'],audit_counter_exposed=False,hidden_event_types_exposed=False,infer_hidden_audit_count_from_delta=False,apply_original_audit_seq_plus_one_rule=False)
                gaps.append('advance_proof_is_synthetic_injection_M03_verifier_missing')
            else:o.update(incremental_apply='paused',repair='bounded_pull_or_snapshot')
        elif kind=='receive_projection_jump':
            receive({'cursor':a['next_cursor']})
            o.update(repair='bounded_pull_or_snapshot',treat_unproved_gap_as_contiguous=False)
        elif kind=='trusted_read_permission_narrows':
            permission_narrowed=True;facts['authority_revision']=a['new_authority_ref']
            state_ref='lab-cleared-after-permission-narrowing';atomic_boundary(db_path,state_ref,current)
            permission_steps.append('clear_affected_projection')
            o.update(restricted_body_exposed=False,stale_read_permission_reactivated=False,reveal_hidden_audit_types_or_counts=False)
        elif kind=='receive_old_permission_projection':
            if permission_narrowed:o['old_projection_applications']=0
            else:gaps.append('old_permission_projection_without_narrowing_evidence')
        elif kind=='request_current_permission_snapshot':
            if permission_narrowed:
                permission_steps.append('request_current_permission_snapshot')
                o.update(operation_order=permission_steps.copy(),different_permission_streams_mixed=False)
                gaps.append('current_permission_snapshot_contents_not_supplied_M03_bootstrap_missing')
            else:gaps.append('new_permission_scope_authority_not_supplied')
        elif kind=='repair_attempt':
            fault=a.get('fault')
            invalid=('snapshot_incomplete','snapshot_cycle','snapshot_digest_mismatch','snapshot_schema_incompatible')
            if fault in invalid or fault in ('pull_failed','cursor_expired'):
                o.update(invalid_snapshot_activations=0,history_completeness_one_of='unavailable' if fault=='pull_failed' else 'partial',safe_reason_present=True,resync_path_present=True,fabricate_complete_history=False,erase_known_success=False)
                if facts.get('known_receipt_ref'):o['known_receipt_ref']=facts['known_receipt_ref']
                gaps.append('repair_fault_metadata_injected_not_actual_snapshot_parser_M03')
            else:gaps.append('unsupported_repair_fault')
        elif kind=='restart_connection':
            epoch=a['new_epoch'];o.update(persistent_domain=copy.deepcopy(current),resume_from_seq=o['durable_cursor']['seq'],seq_reset=False,epoch_numeric_order=False)
            gaps.append('stable_original_intent_and_key_absent_in_initial_facts')
        elif kind in ('old_display_callback','old_retract'):
            if a.get('epoch')==epoch:o['display_updates']+=1
            else:o.update(old_retract_deletes_new_fragment=False)
        elif kind=='old_receipt_hint':
            hint=copy.deepcopy(a);gaps.append('hint_not_authoritative_receipt_D03_M03')
        elif kind=='current_connection_readonly_receipt_lookup':
            if hint and a.get('epoch')==epoch and a.get('matching_identity_and_digest') is True and a.get('authoritative_outcome') in ('succeeded','failed') and all(hint.get(k) for k in ('operation_ref','intent_ref','attempt_ref','payload_digest_ref','source_ref')):
                persist_fact(db_path,'effect',hint['operation_ref'],{'outcome':a['authoritative_outcome'],'digest_ref':hint['payload_digest_ref']})
                verified=read_fact(db_path,'effect',hint['operation_ref'])
                o.update(original_effect=verified['outcome'],additional_business_dispatches=0,discard_real_effect_only_due_epoch=False,hint_alone_generates_authoritative_receipt=False)
                if a.get('receipt_ref'):o['receipt_ref']=a['receipt_ref']
                else:gaps.append('actual_receipt_id_not_supplied')
            else:gaps.append('lookup_missing_complete_identity_digest_or_authority')
        elif kind=='renderer_receipt_claim':o['renderer_claim_is_execution_proof']=False
        elif kind=='slow_subscription_receives':
            limit=facts.get('test_buffer_limit')
            if not limit:gaps.append('measured_buffer_contract_missing');continue
            # Actual queue admits only items fitting both bounds; excess causes
            # pause, no implicit source cursor or command advance.
            count=a['event_count'];total=a['total_bytes'];sizes=[total//count+(i<total%count) for i in range(count)]
            queue=[];used=0
            for size in sizes:
                if len(queue)+1>limit['event_count'] or used+size>limit['bytes']:
                    o.update(subscription_action_one_of='pause',safe_resync_reason_present=True);break
                queue.append(size);used+=size
            o.update(buffer_peak_events_max=len(queue),buffer_peak_bytes_max=used,unbounded_buffer=False,silent_skip=False)
        elif kind=='coincident_facts':
            for ref in a['refs']:persist_fact(db_path,'fact',ref,{'persisted':True})
            o['authoritative_facts_persisted_first']=all(read_fact(db_path,'fact',ref) for ref in a['refs'])
            o.update(business_reexecutions=0,drop_terminal_authority_or_receipt=False)
        elif kind=='compression_and_snapshot_replace_projection':
            o.update(snapshot_does_not_overwrite_independent_draft=True,submission_intent_recreated=False)
        elif kind=='process_exit_then_restart':
            loaded=read_fact(db_path,'pending',pending.get('client_message_ref','lab-pending'))
            permitted=facts.get('effective_policy',{}).get('draft_body_persistence_permitted',False)
            o.update(pending_identity_preserved=bool(loaded and loaded.get('submission_intent_ref')==pending.get('submission_intent_ref')),body_recovery_promised=False,nonrecoverable_body_notice_required=not permitted,retention_duration_created=False,restore_unpermitted_body=False,new_retention_switch_or_default=False)
            if permitted:
                o.pop('body_recovery_promised',None)
                gaps.append('body_plaintext_not_materialized_cannot_demonstrate_body_restore')
        elif kind=='submission_timeout':o['delivery_state_label']='delivery_unknown'
        elif kind=='query_original_acceptance_identity':
            if not pending.get('submission_intent_ref'):gaps.append('submission_identity_missing');continue
            accepted=a.get('trusted_result')=='accepted'
            o.update(delivery_state_label='confirmed_accepted' if accepted else 'delivery_unknown',original_confirmed_message_count=int(accepted),additional_duplicate_confirmed_messages=0,new_submission_intents=0,new_model_turns=0,timeout_means_failed=False,query_without_evidence_means_delivered=False)
            persist_fact(db_path,'delivery',pending['submission_intent_ref'],{'accepted':accepted})
        elif kind=='duplicate_ipc_delivery':o['additional_duplicate_confirmed_messages']=0
        elif kind in ('recover_operation','recover_claimed_operation'):
            proven=a.get('unique_execution_entry') and a.get('durable_dispatch_boundary_proves_zero_dispatch')
            if proven:o.update(effect_phase_label='not_dispatched',continuation_requires_current_scope_capability_business_cas=True,claim_alone_implies_dispatched=False)
            else:o.update(effect_outcome_label='outcome_unknown',receipt_id_precreated=False,unknown_is_failed=False,not_found_proves_never_executed=False,ordinary_confirm_resolves_unknown=False)
            fullallow_risk()
        elif kind=='reconcile_original':
            if not a.get('reliable_effect_evidence'):o['effect_outcome_label']='outcome_unknown'
            else:gaps.append('actual_effect_receipt_and_identity_missing')
        elif kind=='trusted_explicit_user_do_again':
            bindings=a.get('bindings',{});required=('user_instruction_ref','original_unknown_action_ref','original_record_version_ref','display_revision_ref','scope_ref','action_type_ref','normalized_target_ref','normalized_parameter_digest_ref','new_intent_ref','new_plan_digest_ref')
            if a.get('trusted_issuer_fixture') and all(bindings.get(k) for k in required) and facts.get('all_hard_prerequisites_valid'):
                link=copy.deepcopy(bindings);persist_fact(db_path,'new-intent',bindings['new_intent_ref'],{'old_outcome':o.get('old_outcome'),'link_ref':a.get('host_link_ref')})
                o.update(new_intent_ref=bindings['new_intent_ref'],inline_possible_duplicate_notice=True,old_and_new_receipts_independent=True,link_ref_is_authorization_token=False)
                fullallow_risk();gaps.append('synthetic_issuer_injection_not_production_signed_association')
            else:o['host_link_issued']=False
        elif kind=='new_operation_succeeds':
            if link and a.get('new_receipt_ref'):
                persist_fact(db_path,'new-effect',a['new_receipt_ref'],{'outcome':'succeeded','intent_ref':link['new_intent_ref']})
                new_outcome=read_fact(db_path,'new-effect',a['new_receipt_ref'])['outcome']
                o.update(new_outcome=new_outcome,new_receipt_ref=a['new_receipt_ref'],new_success_resolves_old_unknown=False)
            else:gaps.append('new_success_without_trusted_new_link_or_receipt')
        elif kind=='claim_do_again':
            if not a.get('authentic_user_instruction_evidence'):o.update(host_link_issued=False,non_user_event_is_new_intent=False)
            else:gaps.append('actual_user_instruction_and_trusted_binding_missing')
        elif kind=='binding_changes_before_dispatch':
            link=None;o.update(stale_link_dispatches=0,next_operation='reconcile_and_refresh_plan_and_display',blind_dispatch_under_stale_link=False);fullallow_risk()
        elif kind=='evaluate_current_new_intent_plan':
            fullallow_risk()
            if facts.get('all_scope_purpose_capability_business_cas_valid'):o.update(pure_risk_pause=False,hard_prerequisites_checked=True,risk_only_hidden_hold=False)
            else:gaps.append('individual_hard_prerequisites_missing')
        elif kind=='hard_prerequisite_fails':
            link=None;o.update(business_writes=0,result='reject_or_replan_with_true_reason',FullAllow_overrides_hard_prerequisite=False);fullallow_risk()
        elif kind=='trusted_cancel_received_before_commit':
            if a.get('zero_effect_proven'):o.update(business_writes=0,cancellation_terminal_requires_evidence=True,cancel_request_alone_proves_cancelled=False)
            else:gaps.append('zero_effect_evidence_missing')
        elif kind in ('cancel_requested','navigate_close_view'):o.update(process_stop_and_effect_independent=True,navigation_means_business_rollback=False,claim_cancelled_from_request_only=False)
        else:handled=False;processed-=1;gaps.append('unsupported_action:'+str(kind))
    return {'observations':o,'gaps':sorted(set(gaps)),'processed':processed,
            'layer':'policy_and_symbolic_lab_observations_only_no_complete_fixture_operation',
            'action_evidence':action_evidence,
            'observation_provenance':{k:('initial_policy_default_not_operation_evidence' if k in initial_observation_keys else 'decision_or_symbolic_lab_fact_see_action_evidence') for k in o},
            'persistent_boundary':read_boundary(db_path)}
