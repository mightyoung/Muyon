"""Synthetic contract fixture only. No Muyon adapter, Hy engine, HTTP or model IO."""
import json
import sqlite3
from dataclasses import dataclass


@dataclass(frozen=True)
class Outcome:
    status: str
    committed: bool


class FakeVector:
    def __init__(self, fail=False):
        self.fail = fail
        self.ids = {'old'}
        self.calls = 0

    def replace(self):
        self.calls += 1
        if self.fail:
            raise OSError('synthetic vector failure')
        self.ids = {'new'}


class Store:
    """SQL authority plus durable correction barrier; vector index is derived.

    Acceptance of a user correction is a separate durable intent, not a claim
    that replacement succeeded. SQL rollback may retain old history, but that
    history must not become current truth while the accepted correction is pending.
    """
    def __init__(self, path, vector):
        self.db = sqlite3.connect(path, isolation_level=None)
        self.db.executescript('''
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=FULL;
            CREATE TABLE IF NOT EXISTS facts(
                id TEXT PRIMARY KEY, body TEXT NOT NULL, current INTEGER NOT NULL);
            CREATE UNIQUE INDEX IF NOT EXISTS one_current ON facts(current) WHERE current=1;
            CREATE TABLE IF NOT EXISTS control(deleted INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS intent(
                id TEXT PRIMARY KEY, body TEXT NOT NULL, state TEXT NOT NULL);
        ''')
        if not self.db.execute('SELECT count(*) FROM control').fetchone()[0]:
            with self.transaction():
                self.db.execute('INSERT INTO control VALUES(0)')
                self.db.execute("INSERT INTO facts VALUES('old','synthetic: city A',1)")
        self.vector = vector
        self.trace = []

    def transaction(self):
        return Transaction(self.db)

    def accept(self, body='synthetic: city B'):
        with self.transaction():
            if self.deleted():
                raise ValueError('deleted')
            self.db.execute("INSERT INTO intent VALUES('correction',?,'not_committed')", (body,))
        self.trace.append('correction_intent_committed')

    def deleted(self):
        return bool(self.db.execute('SELECT deleted FROM control').fetchone()[0])

    def state(self):
        row = self.db.execute("SELECT state FROM intent WHERE id='correction'").fetchone()
        return row[0] if row else None

    def fail_insert(self):
        # Actual SQLite failure after UPDATE old, not a Python early-return mock.
        self.db.executescript('''CREATE TEMP TRIGGER fail_new BEFORE INSERT ON facts
            WHEN NEW.id='new' BEGIN SELECT RAISE(ABORT,'synthetic insert failure'); END;''')

    def replace(self, after_retire=None, after_sql_commit=None):
        if self.state() != 'not_committed':
            raise ValueError('requires confirmed not_committed; no unknown replay')
        try:
            with self.transaction():
                if self.deleted():
                    raise ValueError('deleted')
                body = self.db.execute('SELECT body FROM intent').fetchone()[0]
                self.db.execute("UPDATE facts SET current=0 WHERE current=1")
                self.trace.append('old_retired_in_transaction')
                if after_retire:
                    after_retire()
                self.db.execute("INSERT INTO facts VALUES('new',?,1)", (body,))
                self.db.execute("UPDATE intent SET state='index_pending'")
            self.trace.append('replacement_sql_committed')
        except sqlite3.Error:
            self.trace.append('replacement_sql_rolled_back')
            return Outcome('NOT_COMMITTED', False)
        if after_sql_commit:
            after_sql_commit()
        return self.rebuild_index()

    def rebuild_index(self):
        # Explicit repair of a known committed derived index, never model replay.
        if self.deleted():
            return Outcome('DELETED', False)
        if self.state() != 'index_pending':
            raise ValueError('no known index work')
        try:
            self.vector.replace()
        except OSError:
            self.trace.append('index_pending')
            return Outcome('COMMITTED_INDEX_PENDING', True)
        self.db.execute("UPDATE intent SET state='ready'")
        self.trace.append('index_ready')
        return Outcome('COMMITTED', True)

    def projection(self):
        if self.deleted():
            return {'status': 'DELETED', 'bodies': []}
        state = self.state()
        if state in ('not_committed', 'unknown'):
            return {'status': state.upper(), 'bodies': []}
        # SQL fallback is explicit: stale/missing vectors cannot hide a commit or
        # revive old truth. This fixture does not implement a production retriever.
        bodies = [r[0] for r in self.db.execute('SELECT body FROM facts WHERE current=1')]
        return {'status': 'INDEX_PENDING' if state == 'index_pending' else 'READY', 'bodies': bodies}

    def delete(self):
        with self.transaction():
            self.db.execute('UPDATE control SET deleted=1')
            self.db.execute('UPDATE facts SET current=0')

    def mark_unknown(self):
        self.db.execute("UPDATE intent SET state='unknown'")

    def close(self):
        self.db.close()


class Transaction:
    def __init__(self, db):
        self.db = db

    def __enter__(self):
        self.db.execute('BEGIN IMMEDIATE')

    def __exit__(self, kind, value, traceback):
        self.db.execute('ROLLBACK' if kind else 'COMMIT')


class ModelFailure(ValueError):
    pass


def parse_operations(body):
    """Missing/blank response is not a valid explicit JSON no-op []."""
    if not isinstance(body, str) or not body.strip():
        raise ModelFailure('EMPTY_MODEL_RESULT')
    try:
        operations = json.loads(body)
    except (ValueError, TypeError) as error:
        raise ModelFailure('INVALID_JSON') from error
    if not isinstance(operations, list):
        raise ModelFailure('INVALID_OPERATIONS')
    for operation in operations:
        if (not isinstance(operation, dict) or set(operation) != {'op', 'body'}
                or operation['op'] != 'REPLACE' or not isinstance(operation['body'], str)
                or not operation['body'].strip()):
            raise ModelFailure('INVALID_OPERATION')
    return operations


class FakeProvider:
    def __init__(self, body=None, unknown=False):
        self.body, self.unknown, self.calls = body, unknown, 0

    def generate(self):
        self.calls += 1
        if self.unknown:
            raise TimeoutError('synthetic outcome unknown')
        return self.body


def propose(provider):
    """One local fake invocation only; no retry scheduler or HTTP transport."""
    try:
        body = provider.generate()
    except TimeoutError:
        return {'status': 'UNKNOWN', 'operations': None}
    try:
        return {'status': 'NO_CHANGE' if not (ops := parse_operations(body)) else 'PROPOSED',
                'operations': ops}
    except ModelFailure as error:
        return {'status': str(error), 'operations': None}


def assert_correction_projection(projection):
    """Oracle shared by normal and deliberately broken implementations."""
    assert 'synthetic: city A' not in projection['bodies'], 'overruled truth'
    assert len(projection['bodies']) <= 1, 'two current facts'
    assert projection['status'] not in ('READY', 'COMMITTED') or projection['bodies'], 'silent empty memory'
