#!/usr/bin/env python3
"""Validate synthetic fixture consistency. This is not a production admission/index DUT."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def check(ok, message):
    if not ok:
        raise ValueError(message)

def digest(text):
    return 'sha256:' + hashlib.sha256(text.encode('utf-8')).hexdigest()

def load(name):
    doc = json.loads((ROOT / name).read_text())
    check(doc['schema_version'] == 1 and doc['synthetic_only'] is True, name + ': scope')
    check(doc['evidence_status'] == 'UNVERIFIED', name + ': evidence claim')
    ids = [case['id'] for case in doc['cases']]
    check(len(ids) == len(set(ids)), name + ': duplicate case id')
    return doc

def validate():
    writer = load('writer.json')
    proposal = writer['proposal_template']
    check(proposal['verification'] == 'candidate', 'writer cannot certify verified memory')
    source = writer['sources'][0]
    check(digest(source['content']) == source['content_digest'], 'source digest')
    check(proposal['source_refs'] == [{key: source[key] for key in ('id','revision','content_digest')}],
          'exact source reference')
    writer_oracle = {
        'all_current':'COMMIT_CANDIDATE', 'cas_changed':'REJECT_CAS',
        'authority_revoked':'REJECT_AUTHORITY', 'policy_closed':'REJECT_POLICY',
        'old_intent_invalidated':'REJECT_INTENT', 'source_revision_changed':'REJECT_SOURCE',
        'source_digest_changed':'REJECT_SOURCE', 'source_missing':'UNKNOWN',
        'source_rights_unknown':'UNKNOWN', 'source_tombstoned':'REJECT_TOMBSTONE',
        'ancestor_tombstoned':'REJECT_TOMBSTONE', 'lineage_unknown':'UNKNOWN',
        'verification_escalation':'REJECT_VERIFICATION', 'effect_request':'REJECT_SCHEMA',
        'same_intent_same_payload':'EXISTING_RECEIPT',
        'same_intent_changed_payload':'REJECT_REPLAY_CONFLICT',
        'durable_commit_receipt_exists':'EXISTING_RECEIPT', 'receipt_unavailable':'UNKNOWN',
        'scope_mismatch':'REJECT_AUTHORITY', 'valid_abstention':'NO_PROPOSAL'}
    check(set(writer_oracle) == {c['host_condition'] for c in writer['cases']}, 'writer coverage')
    for case in writer['cases']:
        expected = writer_oracle[case['host_condition']]
        check(case['expected_host_outcome'] == expected, case['id'] + ': oracle label')
        check(case['expected_business_writes'] == int(expected == 'COMMIT_CANDIDATE'),
              case['id'] + ': duplicate or unsafe write label')
    diff = load('diff-index.json')
    objects = {o['revision']: o for o in diff['content_objects']}
    events = {e['event_id']: e for e in diff['events']}
    check(len(events) == len(diff['events']), 'immutable event uniqueness')
    for obj in objects.values():
        check(digest(obj['content']) == obj['content_digest'], 'content corruption')
    for event in events.values():
        for side in ('base', 'target'):
            check(objects[event[side+'_revision']]['content_digest'] == event[side+'_digest'],
                  event['event_id'] + ': exact content revision')
        check(digest(event['patch']) == event['patch_digest'], 'patch digest')
    # Text equality is deliberately insufficient: two immutable events share literal bytes.
    check(len(events) == 2 and len({e['patch_digest'] for e in events.values()}) == 1,
          'missing same-text distinct-event counterexample')
    for arm in ('baseline_git_event_refs', 'sidecar_candidate_refs'):
        for ref in diff[arm]:
            event = events[ref['event_id']]
            check(all(event.get(k) == v for k,v in ref.items()), arm + ': frozen ref mismatch')
    unknown = {'target_revision_mismatch','digest_fork','replay_conflict','missing_base',
               'corrupt_patch','corrupt_index','stale_generation','coverage_unknown'}
    identity = {'session_text_identity','literal_text_identity'}
    found = {'exact','same_text_distinct_event','idempotent_replay','exact_rename_event'}
    observed_conditions = set()
    for case in diff['cases']:
        condition = case['condition']
        observed_conditions.add(condition)
        expected = ('UNKNOWN' if condition in unknown else 'REJECT_IDENTITY' if condition in identity
                    else 'FOUND' if condition in found else 'REJECT_AUTHORITY' if condition == 'authority_revoked'
                    else 'EMPTY' if condition == 'complete_authorized_empty' else None)
        check(expected is not None and case['expected_status'] == expected, case['id'] + ': oracle label')
        check(bool(case['expected_event_ids']) == (expected == 'FOUND'), case['id'] + ': result identity')
        check(all(i in events for i in case['expected_event_ids']), case['id'] + ': unknown event id')
        check(case['comparison_arms'] == ['baseline_git_event_refs','sidecar_candidate_refs'],
              case['id'] + ': paired comparison')
    check(unknown | identity | found | {'authority_revoked','complete_authorized_empty'} == observed_conditions,
          'diff coverage')
    print(f'PASS fixture consistency: writer={len(writer["cases"])} diff={len(diff["cases"])}; '
          'model_calls=0; DUT_runs=0; benefit=UNVERIFIED')

if __name__ == '__main__':
    validate()
