"""Offline contracts for the retirement prerequisite, not a legacy suite runner."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'experiments/redesign/rust-agent-host-lab/core/tests/fixtures/legacy-schema12'
PIN = '214b4031deb38ca7dfd35ee86396089eb48157d5'
CASES = ['test_stage1_contract', 'test_stage2_data', 'test_stage2_threshold', 'test_kaggle_submit']


class IndependentLaya(unittest.TestCase):
    def test_both_workflows_have_unconditional_independent_job(self):
        for name in ['ci', 'verify']:
            with self.subTest(workflow=name):
                jobs = yaml.load((ROOT / f'.github/workflows/{name}.yml').read_text(), Loader=yaml.BaseLoader)['jobs']
                self.assertIn('laya-offline', jobs, 'Laya must not follow the Flutter step')
                job = jobs['laya-offline']
                self.assertNotIn('needs', job)
                self.assertNotIn('if', job)
                self.assertTrue(any(s.get('run') == 'bash scripts/check_laya_offline.sh' for s in job['steps']))
                self.assertFalse(any('flutter' in (s.get('uses', '') + s.get('run', '')).lower() for s in job['steps']))
                for key, other in jobs.items():
                    if key != 'laya-offline':
                        self.assertFalse(any('test_stage1_contract' in str(s) for s in other['steps']))

    def test_original_flutter_jobs_and_triggers_are_preserved(self):
        for name in ['ci', 'verify']:
            before = yaml.load(subprocess.check_output(['git', 'show', f'{PIN}:.github/workflows/{name}.yml'], cwd=ROOT, text=True), Loader=yaml.BaseLoader)
            after = yaml.load((ROOT / f'.github/workflows/{name}.yml').read_text(), Loader=yaml.BaseLoader)
            self.assertEqual(before['on'], after['on'])
            for key, job in before['jobs'].items():
                job['steps'] = [s for s in job['steps'] if not s.get('name', '').startswith('Laya script tests')]
                self.assertEqual(job, after['jobs'][key], 'coverage/analyze/test/artifact configuration must stay intact')
            self.assertNotIn('continue-on-error', after['jobs']['laya-offline'])
            self.assertTrue(all('continue-on-error' not in step for step in after['jobs']['laya-offline']['steps']))

    def invoke(self, failure=''):
        runner = ROOT / 'scripts/check_laya_offline.sh'
        self.assertTrue(runner.is_file(), 'independent runner is missing')
        with tempfile.TemporaryDirectory() as tmp:
            temp = Path(tmp)
            shim = temp / 'python3'
            shim.write_text('#!/bin/bash\nprintf "%s:%s\\n" "$PWD" "$*" >> "$TRACE"\n[[ "$*" != "$FAIL_CASE.py" ]] || exit 17\n')
            shim.chmod(0o755)
            trace = temp / 'trace'
            env = {**os.environ, 'PATH': str(temp) + os.pathsep + '/usr/bin:/bin',
                   'TRACE': str(trace), 'FAIL_CASE': failure}
            result = subprocess.run(['bash', str(runner)], cwd=tmp, env=env, capture_output=True, text=True)
            calls = trace.read_text().splitlines() if trace.exists() else []
            return result.returncode, calls

    def test_runner_executes_all_four_from_correct_directory_without_flutter(self):
        code, calls = self.invoke()
        self.assertEqual(code, 0)
        self.assertEqual(calls, [f'{ROOT / "scripts/laya"}:{name}.py' for name in CASES])

    def test_any_failed_child_fails_the_gate(self):
        for i, name in enumerate(CASES):
            with self.subTest(case=name):
                code, calls = self.invoke(name)
                self.assertEqual(code, 17)
                self.assertEqual(len(calls), i + 1)


class FrozenSchema(unittest.TestCase):
    def manifest(self):
        file = FIXTURE / 'manifest.json'
        self.assertTrue(file.is_file(), 'frozen reference manifest is missing')
        return json.loads(file.read_text())

    def test_exact_historical_source_bytes_are_preserved(self):
        data = self.manifest()
        self.assertEqual(data['source_sha'], PIN)
        self.assertEqual(set(data['files']), {'store.dart', 'entities.dart'})
        for name, entry in data['files'].items():
            historical = subprocess.check_output(['git', 'show', f'{PIN}:{entry["source_path"]}'], cwd=ROOT)
            self.assertEqual((FIXTURE / name).read_bytes(), historical)
            self.assertEqual(entry['sha256'], hashlib.sha256(historical).hexdigest())

    def test_rust_test_consumes_frozen_reference_without_removing_assertions(self):
        path = ROOT / 'experiments/redesign/rust-agent-host-lab/core/tests/supplier_store.rs'
        source = path.read_text()
        self.assertNotIn('include_str!("../../../../../packages/', source)
        self.assertIn('include_str!("fixtures/legacy-schema12/store.dart")', source)
        self.assertIn('include_str!("fixtures/legacy-schema12/entities.dart")', source)
        previous = subprocess.check_output(['git', 'show', f'{PIN}:{path.relative_to(ROOT)}'], cwd=ROOT, text=True)
        expected = previous.replace('../../../../../packages/supplier_core/lib/src/', 'fixtures/legacy-schema12/')
        self.assertEqual(source, expected, 'only include paths change; all real Rust assertions remain')

    def test_historical_reference_manifest_matches_fixed_git_objects(self):
        path = ROOT / 'docs/legacy/flutter-source-manifest.json'
        self.assertTrue(path.is_file(), 'historical source references are not fixed yet')
        manifest = json.loads(path.read_text())
        self.assertEqual(manifest['legacy_source_sha'], PIN)
        self.assertEqual(manifest['legacy_ci']['status'], 'FAILED')
        for entry in manifest['references']:
            source = subprocess.check_output(['git', 'show', entry['source_sha'] + ':' + entry['source_path']], cwd=ROOT)
            self.assertEqual(hashlib.sha256(source).hexdigest(), entry['sha256'])
        for path in ['crates/muyon-core/Cargo.toml', '.github/workflows/muyon-product.yml',
                     'apps/muyon_android/prepare-model-assets.py', 'scripts/coverage/baseline.json']:
            previous = subprocess.check_output(['git', 'show', PIN + ':' + path], cwd=ROOT)
            self.assertEqual((ROOT / path).read_bytes(), previous)

    def test_reference_checker_rejects_corruption_and_missing_file(self):
        self.manifest()
        checker = ROOT / 'scripts/check_legacy_schema_reference.py'
        self.assertTrue(checker.is_file(), 'reference checker is missing')
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / 'fixture'
            shutil.copytree(FIXTURE, copy)
            def check():
                return subprocess.run(['python3', str(checker), str(copy)], capture_output=True).returncode
            self.assertEqual(check(), 0)
            original = (copy / 'store.dart').read_bytes()
            (copy / 'store.dart').write_bytes(original + b'\n// altered\n')
            self.assertNotEqual(check(), 0)
            (copy / 'store.dart').write_bytes(original)
            (copy / 'entities.dart').unlink()
            self.assertNotEqual(check(), 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
