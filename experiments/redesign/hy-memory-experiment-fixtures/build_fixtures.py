"""Regenerate public synthetic fixtures only; no model, network, or application imports."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def digest(value):
    return 'sha256:' + hashlib.sha256(value.encode('utf-8')).hexdigest()

def save(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

sources = [dict(id='source-synthetic-1', revision=3, content='Synthetic project uses copper labels.',
                content_digest=digest('Synthetic project uses copper labels.'))]
base = dict(intent_id='intent-synthetic-1', object_id='memory-synthetic-1', expected_revision=7,
            authority_revision=4, policy_generation=2, source_refs=[dict(id=sources[0]['id'], revision=3,
            content_digest=sources[0]['content_digest'])], content='Synthetic project uses copper labels.',
            verification='candidate', lineage=['source-synthetic-1'])
# Labels describe required future host behavior, not an implemented host validator.
writer_specs = [
 ('valid_candidate', 'all_current', 'COMMIT_CANDIDATE'),
 ('manual_edit_race', 'cas_changed', 'REJECT_CAS'),
 ('authority_revoked', 'authority_revoked', 'REJECT_AUTHORITY'),
 ('policy_closed_after_queue', 'policy_closed', 'REJECT_POLICY'),
 ('policy_closed_then_reopened', 'old_intent_invalidated', 'REJECT_INTENT'),
 ('source_revision_changed', 'source_revision_changed', 'REJECT_SOURCE'),
 ('same_revision_digest_fork', 'source_digest_changed', 'REJECT_SOURCE'),
 ('source_missing', 'source_missing', 'UNKNOWN'),
 ('source_rights_unknown', 'source_rights_unknown', 'UNKNOWN'),
 ('forgotten_source', 'source_tombstoned', 'REJECT_TOMBSTONE'),
 ('forgotten_ancestor', 'ancestor_tombstoned', 'REJECT_TOMBSTONE'),
 ('missing_lineage', 'lineage_unknown', 'UNKNOWN'),
 ('writer_claims_verified', 'verification_escalation', 'REJECT_VERIFICATION'),
 ('writer_requests_tool', 'effect_request', 'REJECT_SCHEMA'),
 ('duplicate_delivery', 'same_intent_same_payload', 'EXISTING_RECEIPT'),
 ('intent_payload_conflict', 'same_intent_changed_payload', 'REJECT_REPLAY_CONFLICT'),
 ('crash_commit_ack_lost', 'durable_commit_receipt_exists', 'EXISTING_RECEIPT'),
 ('receipt_unavailable', 'receipt_unavailable', 'UNKNOWN'),
 ('cross_scope_source', 'scope_mismatch', 'REJECT_AUTHORITY'),
 ('empty_supported_proposal', 'valid_abstention', 'NO_PROPOSAL'),
]
save('writer.json', dict(schema_version=1, synthetic_only=True, evidence_status='UNVERIFIED',
    sources=sources, proposal_template=base, cases=[dict(id=name, host_condition=condition,
    expected_host_outcome=outcome, expected_business_writes=1 if outcome=='COMMIT_CANDIDATE' else 0)
    for name, condition, outcome in writer_specs]))

before = 'label = "copper"\n'
after = 'label = "silver"\n'
patch = '-label = "copper"\n+label = "silver"\n'
event = dict(event_id='event-synthetic-0001', repository_id='repo-synthetic-1',
             path='src/synthetic_label.py', base_revision='revision-synthetic-base-1',
             target_revision='revision-synthetic-target-2', base_digest=digest(before),
             target_digest=digest(after), patch_digest=digest(patch), patch=patch)
# Explicit host/Git event identity is distinct from display text and session labels.
refs = dict(repository_id=event['repository_id'], event_id=event['event_id'],
            base_revision=event['base_revision'], target_revision=event['target_revision'],
            base_digest=event['base_digest'], target_digest=event['target_digest'], patch_digest=event['patch_digest'])
specs = [
 ('exact_event', 'exact', 'FOUND', [event['event_id']]),
 ('same_text_other_event', 'same_text_distinct_event', 'FOUND', ['event-synthetic-0002']),
 ('session_label_only', 'session_text_identity', 'REJECT_IDENTITY', []),
 ('patch_literal_only', 'literal_text_identity', 'REJECT_IDENTITY', []),
 ('changed_target_revision', 'target_revision_mismatch', 'UNKNOWN', []),
 ('same_revision_digest_fork', 'digest_fork', 'UNKNOWN', []),
 ('duplicate_identical_event', 'idempotent_replay', 'FOUND', [event['event_id']]),
 ('duplicate_conflicting_event', 'replay_conflict', 'UNKNOWN', []),
 ('missing_base', 'missing_base', 'UNKNOWN', []),
 ('corrupt_patch', 'corrupt_patch', 'UNKNOWN', []),
 ('corrupt_index', 'corrupt_index', 'UNKNOWN', []),
 ('index_stale_generation', 'stale_generation', 'UNKNOWN', []),
 ('revoked_source', 'authority_revoked', 'REJECT_AUTHORITY', []),
 ('confirmed_no_match', 'complete_authorized_empty', 'EMPTY', []),
 ('partial_history', 'coverage_unknown', 'UNKNOWN', []),
 ('path_rename', 'exact_rename_event', 'FOUND', [event['event_id']]),
]
event2 = dict(event, event_id='event-synthetic-0002')
save('diff-index.json', dict(schema_version=1, synthetic_only=True, evidence_status='UNVERIFIED',
    content_objects=[dict(revision=event['base_revision'], content=before, content_digest=digest(before)),
                     dict(revision=event['target_revision'], content=after, content_digest=digest(after))],
    events=[event,event2], baseline_git_event_refs=[refs,dict(refs,event_id=event2['event_id'])],
    sidecar_candidate_refs=[refs,dict(refs,event_id=event2['event_id'])],
    cases=[dict(id=name, condition=condition, expected_status=status, expected_event_ids=ids,
                comparison_arms=['baseline_git_event_refs','sidecar_candidate_refs'])
           for name,condition,status,ids in specs]))
