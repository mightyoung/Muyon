import os
import subprocess
import sys
import sqlite3
import tempfile
import unittest
from pathlib import Path

from failure_lab import FakeProvider, FakeVector, ModelFailure, Store, parse_operations, propose, assert_correction_projection


class ReplacementTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'synthetic.db'
        self.vector = FakeVector()
        self.store = Store(self.path, self.vector)
        self.addCleanup(lambda: self.store.close())

    def reopen(self):
        self.store.close()
        self.store = Store(self.path, self.vector)

    def test_insert_failure_rolls_back_sql_but_does_not_restore_overruled_truth(self):
        self.store.accept()
        self.store.fail_insert()
        outcome = self.store.replace()
        self.assertEqual((outcome.status, outcome.committed), ('NOT_COMMITTED', False))
        self.assertEqual(self.store.trace[-2:], ['old_retired_in_transaction', 'replacement_sql_rolled_back'])
        self.assertEqual(self.vector.calls, 0)
        self.assertEqual(self.store.db.execute('SELECT id,current FROM facts').fetchall(), [('old', 1)])
        self.reopen()
        self.assertEqual(self.store.projection(), {'status': 'NOT_COMMITTED', 'bodies': []})
        assert_correction_projection(self.store.projection())

    def test_observer_cannot_see_half_replacement(self):
        self.store.accept()
        observer = Store(self.path, self.vector)
        self.addCleanup(observer.close)
        def during_transaction():
            self.assertEqual(observer.projection(), {'status': 'NOT_COMMITTED', 'bodies': []})
            self.assertEqual(observer.db.execute('SELECT id FROM facts WHERE current=1').fetchall(), [('old',)])
        self.store.replace(after_retire=during_transaction)
        self.assertEqual(observer.projection(), {'status': 'READY', 'bodies': ['synthetic: city B']})

    def test_vector_failure_reports_committed_pending_and_sql_fallback(self):
        self.vector.fail = True
        self.store.accept()
        outcome = self.store.replace()
        self.assertEqual((outcome.status, outcome.committed), ('COMMITTED_INDEX_PENDING', True))
        self.assertEqual(self.vector.ids, {'old'})  # Hostile stale index really remains.
        self.reopen()
        self.assertEqual(self.store.projection(), {'status': 'INDEX_PENDING', 'bodies': ['synthetic: city B']})
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM facts WHERE current=1').fetchone()[0], 1)

    def test_explicit_index_repair_does_not_repeat_sql_or_provider(self):
        self.vector.fail = True
        self.store.accept()
        self.store.replace()
        self.reopen()
        self.vector.fail = False
        self.assertEqual(self.store.rebuild_index().status, 'COMMITTED')
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM facts').fetchone()[0], 2)
        self.assertEqual(self.vector.ids, {'new'})
        self.assertEqual(self.vector.calls, 2)

    def test_known_not_committed_can_be_explicitly_repaired_after_reopen(self):
        self.store.accept()
        self.store.fail_insert()
        self.store.replace()
        self.reopen()  # TEMP fault trigger is gone, durable intent remains.
        self.assertEqual(self.store.replace().status, 'COMMITTED')
        self.assertEqual(self.store.projection()['bodies'], ['synthetic: city B'])

    def test_unique_index_rejects_two_current_facts(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.db.execute("INSERT INTO facts VALUES('bad','synthetic',1)")

    def test_delete_after_sql_failure_blocks_late_repair(self):
        self.store.accept()
        self.store.fail_insert()
        self.store.replace()
        self.store.delete()
        self.reopen()
        with self.assertRaisesRegex(ValueError, 'deleted'):
            self.store.replace()
        self.assertEqual(self.store.projection(), {'status': 'DELETED', 'bodies': []})
        self.assertEqual(self.vector.calls, 0)

    def test_delete_after_vector_failure_blocks_late_index_repair(self):
        self.vector.fail = True
        self.store.accept()
        self.store.replace()
        self.store.delete()
        self.reopen()
        self.vector.fail = False
        self.assertEqual(self.store.rebuild_index().status, 'DELETED')
        self.assertEqual(self.vector.calls, 1)
        self.assertEqual(self.store.projection()['bodies'], [])

    def test_unknown_state_survives_reopen_and_is_not_replayed(self):
        self.store.accept()
        self.store.mark_unknown()
        self.reopen()
        for _ in range(3):
            with self.assertRaisesRegex(ValueError, 'no unknown replay'):
                self.store.replace()
            self.assertEqual(self.store.projection(), {'status': 'UNKNOWN', 'bodies': []})
        self.assertEqual(self.vector.calls, 0)

    def test_success_has_single_new_current_and_preserves_old_history(self):
        self.store.accept()
        self.assertEqual(self.store.replace().status, 'COMMITTED')
        self.reopen()
        self.assertEqual(self.store.db.execute('SELECT id,current FROM facts ORDER BY id').fetchall(), [('new', 1), ('old', 0)])
        self.assertEqual(self.store.projection()['bodies'], ['synthetic: city B'])

    def crash_worker(self, stage):
        code = """
import os, sys
from failure_lab import Store, FakeVector
s = Store(sys.argv[1], FakeVector())
if sys.argv[2] == 'before':
    s.replace(after_retire=lambda: os._exit(71))
else:
    s.replace(after_sql_commit=lambda: os._exit(72))
"""
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
        return subprocess.run([sys.executable, '-c', code, str(self.path), stage],
                              cwd=Path(__file__).parent, env=env, timeout=10).returncode

    def test_process_exit_between_retire_and_insert_keeps_pending_correction(self):
        self.store.accept()
        self.store.close()
        self.assertEqual(self.crash_worker('before'), 71)
        self.store = Store(self.path, self.vector)
        self.assertEqual(self.store.state(), 'not_committed')
        self.assertEqual(self.store.db.execute('SELECT id FROM facts WHERE current=1').fetchall(), [('old',)])
        assert_correction_projection(self.store.projection())

    def test_process_exit_after_sql_commit_preserves_rebuildable_new_truth(self):
        self.store.accept()
        self.store.close()
        self.assertEqual(self.crash_worker('after'), 72)
        self.store = Store(self.path, self.vector)
        self.assertEqual(self.store.state(), 'index_pending')
        self.assertEqual(self.store.projection()['bodies'], ['synthetic: city B'])
        assert_correction_projection(self.store.projection())
        self.assertEqual(self.store.rebuild_index().status, 'COMMITTED')


class ModelTests(unittest.TestCase):
    def test_none_empty_and_whitespace_are_failures_without_fake_success(self):
        for body in (None, '', ' ', '\n\t', '\u3000'):
            with self.subTest(body=repr(body)):
                provider = FakeProvider(body)
                self.assertEqual(propose(provider), {'status': 'EMPTY_MODEL_RESULT', 'operations': None})
                self.assertEqual(provider.calls, 1)

    def test_explicit_json_empty_list_is_legitimate_no_change(self):
        for body in ('[]', ' \n [ ] \t'):
            self.assertEqual(propose(FakeProvider(body)), {'status': 'NO_CHANGE', 'operations': []})

    def test_missing_non_json_and_wrong_shapes_do_not_become_no_change(self):
        for body in ('null', '{}', 'false', '""', '[null]', '[{}]', '[', 'garbage', []):
            with self.subTest(body=repr(body)):
                with self.assertRaises(ModelFailure):
                    parse_operations(body)

    def test_valid_operation_is_only_a_proposal(self):
        self.assertEqual(propose(FakeProvider('[{"op":"REPLACE","body":"synthetic city B"}]')),
                         {'status': 'PROPOSED', 'operations': [{'op': 'REPLACE', 'body': 'synthetic city B'}]})

    def test_unknown_fake_provider_is_invoked_once(self):
        provider = FakeProvider(unknown=True)
        self.assertEqual(propose(provider), {'status': 'UNKNOWN', 'operations': None})
        self.assertEqual(provider.calls, 1)

    def test_invalid_model_body_leaves_store_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            store = Store(Path(directory) / 'synthetic.db', FakeVector())
            try:
                before = store.projection()
                self.assertEqual(propose(FakeProvider(' '))['status'], 'EMPTY_MODEL_RESULT')
                self.assertIsNone(store.state())
                self.assertEqual(store.projection(), before)
            finally:
                store.close()


class OracleSensitivityTests(unittest.TestCase):
    """Broken fixtures are intentional negative controls, not product code."""
    def test_oracle_rejects_legacy_autocommit_retire_then_failed_insert(self):
        db = sqlite3.connect(':memory:', isolation_level=None)
        self.addCleanup(db.close)
        db.executescript("CREATE TABLE f(id TEXT PRIMARY KEY,current INTEGER); INSERT INTO f VALUES('old',1);")
        db.execute("UPDATE f SET current=0 WHERE id='old'")
        try:
            db.execute("INSERT INTO f VALUES('old',1)")
        except sqlite3.IntegrityError:
            pass  # Broken implementation silently calls this success.
        result = {'status': 'COMMITTED', 'bodies': db.execute('SELECT id FROM f WHERE current=1').fetchall()}
        with self.assertRaisesRegex(AssertionError, 'silent empty memory'):
            assert_correction_projection(result)

    def test_oracle_rejects_rollback_that_reactivates_overruled_truth(self):
        with tempfile.TemporaryDirectory() as directory:
            store = Store(Path(directory) / 'synthetic.db', FakeVector())
            try:
                store.accept()
                store.fail_insert()
                store.replace()
                # Mutant omits the pending correction barrier on SQL rollback.
                bodies = [row[0] for row in store.db.execute('SELECT body FROM facts WHERE current=1')]
                with self.assertRaisesRegex(AssertionError, 'overruled truth'):
                    assert_correction_projection({'status': 'READY', 'bodies': bodies})
            finally:
                store.close()

    def test_oracle_rejects_blank_as_no_change_mutant(self):
        broken = lambda body: [] if not body.strip() else parse_operations(body)
        with self.assertRaises(AssertionError):
            with self.assertRaises(ModelFailure):
                broken(' ')


if __name__ == '__main__':
    unittest.main(verbosity=2)
