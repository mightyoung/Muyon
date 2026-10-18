"""Run local synthetic tests and save bounded evidence in the authorized docs tree."""
import contextlib
import io
import json
import platform
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

from failure_lab import FakeVector, Store

ROOT = Path(__file__).resolve().parents[3]
LAB = Path(__file__).resolve().parent
DOCS = ROOT / 'docs/tasks/memory-failure-validation-20261018'
BASE = '6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa'


def scenario(sql_fail=False, vector_fail=False):
    with tempfile.TemporaryDirectory() as directory:
        vector = FakeVector(fail=vector_fail)
        store = Store(Path(directory) / 'synthetic.db', vector)
        try:
            store.accept()
            if sql_fail:
                store.fail_insert()
            outcome = store.replace()
            return {'status': outcome.status, 'committed': outcome.committed,
                    'projection': store.projection(), 'trace': store.trace,
                    'vector_calls': vector.calls, 'vector_ids': sorted(vector.ids)}
        finally:
            store.close()


def main():
    log = io.StringIO()
    suite = unittest.defaultTestLoader.discover(str(LAB), pattern='test_*.py')
    with contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    DOCS.mkdir(parents=True, exist_ok=True)
    (DOCS / 'python-tests.txt').write_text(log.getvalue())
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    evidence = {'source_head_at_run': revision, 'baseline': BASE,
                'scope': 'SYNTHETIC_CONTRACT_ONLY', 'python': platform.python_version(),
                'sqlite': sqlite3.sqlite_version, 'tests': result.testsRun,
                'failures': len(result.failures), 'errors': len(result.errors),
                'skipped': len(result.skipped), 'success': result.wasSuccessful(),
                'scenarios': {'insert_failure': scenario(sql_fail=True),
                              'vector_failure': scenario(vector_fail=True),
                              'success': scenario()},
                'actual_adapter_canary': 'NOT_RUN: Dart/Flutter SDK unavailable',
                'old_hy_24_tests': 'NOT_RUN: Cargo unavailable; source/blob inventory only',
                'i04_operation': 'NOT_EXECUTED: prior denial preserved; no retry/reroute'}
    (DOCS / 'results.json').write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: evidence[k] for k in ('tests', 'failures', 'errors', 'skipped', 'success', 'source_head_at_run')}))
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(main())
