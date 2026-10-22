"""Source-SQL checks only: no Rust compilation, policy or dispatcher execution."""
import json
import pathlib
import re
import sqlite3
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
ARTIFACTS = ROOT / 'crates/muyon-core/src/artifacts'
local = (ARTIFACTS / 'local_interactions.rs').read_text()
shared = (ARTIFACTS / 'save_journal.rs').read_text()
base = (ARTIFACTS / 'mod.rs').read_text()
project = (ARTIFACTS / 'project_access.rs').read_text()

def sql_literal(source, prefix, contains=None):
    choices = re.findall(r'"([^"\n]+)"', source)
    choices = [value for value in choices if value.startswith(prefix) and (contains is None or contains in value)]
    assert choices, (prefix, contains)
    return choices[0]

binding_query = sql_literal(local, 'SELECT CASE WHEN length(CAST(binding_json AS BLOB))<=8192', 'AND active=1')
binding_issue = sql_literal(local, 'INSERT INTO artifact_local_bindings_v1 VALUES')
pending_insert = sql_literal(shared, 'INSERT INTO artifact_local_intents_v1 VALUES')
receipt_update = sql_literal(shared, "UPDATE artifact_local_intents_v1 SET status='committed'")
local_lookup = sql_literal(local, 'SELECT CASE WHEN length(CAST(binding_digest AS BLOB))<=64', 'AND actor_id=?')
pending_query = sql_literal(local, 'SELECT CASE WHEN length(CAST(intent_id AS BLOB))<=128')
form_insert = sql_literal(local, 'INSERT INTO artifact_local_forms_v1 VALUES')
form_update = sql_literal(local, 'UPDATE artifact_local_forms_v1 SET revision=')
review_insert = sql_literal(local, 'INSERT INTO artifact_local_reviews_v1 VALUES')
review_lookup = sql_literal(local, 'SELECT CASE WHEN length(CAST(request_json AS BLOB))<=16384', 'AND actor_id=?')

with tempfile.TemporaryDirectory(prefix='local-independent-') as directory:
    path = directory + '/synthetic.sqlite'
    db = sqlite3.connect(path)
    db.execute('PRAGMA foreign_keys=ON')
    db.execute('CREATE TABLE projects(id TEXT PRIMARY KEY)')
    db.execute("INSERT INTO projects VALUES('project')")
    db.execute("INSERT INTO projects VALUES('other-project')")
    created = []
    for source in (base, project, local):
        for name, ddl in re.findall(r'\("(\w+)"\s*,\s*"(CREATE TABLE [^"]+)"\)', source):
            db.execute(ddl)
            assert db.execute('SELECT sql FROM sqlite_master WHERE name=?', (name,)).fetchone()[0] == ddl
            created.append(name)
    assert len([name for name in created if name.startswith('artifact_local_')]) == 6
    reference = '{"synthetic":"original-message-revision-1-component-0-attempt"}'
    kind = '{"kind":"form","spec":{"fields":["text"],"single_options":[],"multiple_options":[]}}'
    db.execute(binding_issue, ('project', 'actor', 'form', reference, kind, '1', 'project-grant', '1', 'epoch', '9999999999999'))
    binding = ('project', 'actor', 'form', '1', 'project-grant', '1', 'epoch')
    assert db.execute(binding_query, binding).fetchone()[:2] == (reference, kind)
    for index, replacement in [(0, 'other-project'), (1, 'another-actor'), (2, 'other-object'), (3, '2'), (4, 'document-grant'), (5, '2'), (6, 'old-epoch')]:
        changed = list(binding)
        changed[index] = replacement
        assert db.execute(binding_query, changed).fetchall() == []
    db.execute("UPDATE artifact_local_bindings_v1 SET active=0")
    assert db.execute(binding_query, binding).fetchall() == []
    db.execute("UPDATE artifact_local_bindings_v1 SET active=1")
    db.execute(pending_insert, ('intent', 'project', 'actor', 'digest', '{"synthetic":true}', 'form'))
    db.commit()
    assert db.execute(pending_query, ('project', 'actor', 'form')).fetchone()[0] == 'intent'
    assert db.execute(pending_query, ('project', 'another-actor', 'form')).fetchall() == []
    assert db.execute(pending_query, ('other-project', 'actor', 'form')).fetchall() == []
    assert len(db.execute(local_lookup, ('intent', 'project', 'actor')).fetchall()) == 1
    assert db.execute(local_lookup, ('intent', 'project', 'another-actor')).fetchall() == []
    assert db.execute(local_lookup, ('absent', 'project', 'another-actor')).fetchall() == []
    db.execute("CREATE TRIGGER local_tail AFTER UPDATE ON artifact_local_intents_v1 WHEN NEW.status='committed' BEGIN UPDATE artifact_local_bindings_v1 SET active=0; END")
    db.commit()
    db.execute('BEGIN IMMEDIATE')
    db.execute(form_insert, ('project', 'actor', 'form', '1', '{"synthetic":"manual-value"}'))
    assert db.execute(receipt_update, ('{"synthetic":"receipt"}', 'intent', 'digest')).rowcount == 1
    assert db.execute(binding_query, binding).fetchall() == []
    db.rollback()  # Models the inspected Rust effect Transaction's error Drop.
    assert db.execute('SELECT * FROM artifact_local_forms_v1').fetchall() == []
    assert db.execute("SELECT status,receipt_json,error FROM artifact_local_intents_v1 WHERE intent_id='intent'").fetchone() == ('pending', None, None)
    assert len(db.execute(binding_query, binding).fetchall()) == 1
    db.execute('DROP TRIGGER local_tail')
    db.execute('CREATE TABLE synthetic_policy(value TEXT)')
    db.execute('INSERT INTO synthetic_policy VALUES(?)', ('{"kind":"feedback"}',))
    db.execute("CREATE TRIGGER local_policy_tail AFTER UPDATE ON artifact_local_intents_v1 WHEN NEW.status='committed' BEGIN UPDATE artifact_local_bindings_v1 SET kind_json=(SELECT value FROM synthetic_policy); END")
    db.commit()
    db.execute('BEGIN IMMEDIATE')
    db.execute(form_insert, ('project', 'actor', 'form', '1', '{"synthetic":"manual-value"}'))
    db.execute(receipt_update, ('{"synthetic":"receipt"}', 'intent', 'digest'))
    assert db.execute(binding_query, binding).fetchone()[1] != kind
    db.rollback()
    assert db.execute('SELECT * FROM artifact_local_forms_v1').fetchall() == []
    assert db.execute("SELECT status,receipt_json FROM artifact_local_intents_v1 WHERE intent_id='intent'").fetchone() == ('pending', None)
    assert db.execute(binding_query, binding).fetchone()[1] == kind
    db.execute('DROP TRIGGER local_policy_tail')
    db.execute(form_insert, ('project', 'actor', 'form', '1', '{"synthetic":"old-value"}'))
    db.commit()
    assert db.execute(form_update, ('2', '{"synthetic":"new-value"}', 'project', 'actor', 'form', '1')).rowcount == 1
    assert db.execute(form_update, ('2', '{"synthetic":"stale"}', 'project', 'actor', 'form', '1')).rowcount == 0
    assert db.execute(form_update, ('3', '{}', 'project', 'another-actor', 'form', '2')).rowcount == 0
    db.execute(review_insert, ('preview', 'project', 'actor', '{"synthetic":"frozen-values-and-authority"}', 'preview-digest'))
    db.commit()
    assert db.execute(review_lookup, ('preview', 'project', 'actor')).fetchone() == ('{"synthetic":"frozen-values-and-authority"}', 'preview-digest')
    assert db.execute(review_lookup, ('preview', 'project', 'another-actor')).fetchall() == []
    # Both domains may have the same ID; SQL routing must keep records separate.
    artifact_pending = sql_literal(shared, 'INSERT INTO artifact_save_intents_v1 VALUES')
    db.execute(artifact_pending, ('intent', 'project', 'actor', 'artifact-digest', '{"artifact":true}'))
    db.commit()
    assert db.execute(local_lookup, ('intent', 'project', 'actor')).fetchone()[0] == 'digest'
    assert db.execute("SELECT binding_digest FROM artifact_save_intents_v1 WHERE intent_id='intent'").fetchone()[0] == 'artifact-digest'
    db.close()
    db = sqlite3.connect(path)
    assert db.execute("SELECT status,receipt_json FROM artifact_local_intents_v1 WHERE intent_id='intent'").fetchone() == ('pending', None)
    assert db.execute("SELECT payload FROM artifact_local_forms_v1").fetchone()[0] == '{"synthetic":"new-value"}'
    db.close()

old = subprocess.check_output(['git', 'show', 'de3ec5b56de80f30c5a98c0b22bae64ece6167ae:crates/muyon-core/src/artifacts/save_journal.rs'], cwd=ROOT, text=True)
def artifact_sql(source):
    return {value for value in re.findall(r'"([^"\n]+)"', source) if value.startswith(('SELECT ', 'INSERT ', 'UPDATE ')) and 'artifact_save_intents_v1' in value}
assert artifact_sql(old) == artifact_sql(shared)
print(json.dumps({
    'six_local_table_ddl_roundtrip': 'PASS',
    'binding_scope_actor_object_generation_grant_epoch_revocation_sql': 'PASS',
    'object_pending_and_own_lookup_sql': 'PASS',
    'real_receipt_trigger_rolls_back_local_effect_and_preserves_pending': 'PASS',
    'valid_kind_policy_replacement_detectable_at_tail_sql': 'PASS',
    'form_cas_and_frozen_review_actor_filter_sql': 'PASS',
    'artifact_local_journal_domain_isolation': 'PASS',
    'artifact_domain_sql_identical_to_fixed_base': 'PASS',
    'restart_retains_pending_and_confirmed_values': 'PASS',
    'rust_compile_tests_policy_expiry_masks_digest_confirmation_and_no_retry': 'NOT_RUN or STATIC_REVIEW_ONLY',
}, sort_keys=True))
