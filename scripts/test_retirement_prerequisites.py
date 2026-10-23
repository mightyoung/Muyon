"""Offline contracts for the retirement prerequisite, not a legacy suite runner."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'experiments/redesign/rust-agent-host-lab/core/tests/fixtures/legacy-schema12'
SOURCE_PIN = '214b4031deb38ca7dfd35ee86396089eb48157d5'
GATE_BASE = '4d15b990f725d41a43b86fcd2b170b2219a6f766'
SOURCE_MANIFEST_SHA256 = 'da274faeb9bb67790a68bf56d08a0c6380c8d2e05719bfa7ab7e28c026f9a119'
CASES = ['test_stage1_contract', 'test_stage2_data', 'test_stage2_threshold', 'test_kaggle_submit']
PROVENANCE_PINS = [SOURCE_PIN, '01e56cc2d729dab70e1b1def05c3aa93b28f421a',
                   '8c5995515fa14ca3592a1c33c71afb4e4c1e5def', GATE_BASE]


def product_gate_matches_historical(previous, current, root_toolchain_present):
    """Permit only the reviewed root-input addition; freeze every job byte."""
    if not root_toolchain_present:
        return current == previous
    anchor = b'    paths: &product_paths\n'
    if previous.count(anchor) != 1:
        return False
    expected = previous.replace(anchor, anchor + b"      - 'rust-toolchain.toml'\n", 1)
    return current == expected


class IndependentLaya(unittest.TestCase):
    def test_provenance_is_required_in_both_independent_jobs(self):
        for name in ['ci', 'verify']:
            with self.subTest(workflow=name):
                job = yaml.load((ROOT / f'.github/workflows/{name}.yml').read_text(), Loader=yaml.BaseLoader)['jobs']['laya-offline']
                fetch = [step for step in job['steps'] if step.get('name') == 'Fetch immutable provenance commits']
                self.assertEqual(len(fetch), 1)
                self.assertEqual(shlex.split(fetch[0]['run']), ['git', 'fetch', '--no-tags', '--depth=1', 'origin', *PROVENANCE_PINS])
                checks = [step for step in job['steps'] if step.get('name') == 'Verify frozen references and prerequisite contracts']
                self.assertEqual(len(checks), 1)
                self.assertEqual(checks[0]['run'].strip(), 'python3 -B scripts/check_legacy_schema_reference.py\npython3 -B scripts/test_retirement_prerequisites.py')
                self.assertLess(job['steps'].index(fetch[0]), job['steps'].index(checks[0]))
                self.assertTrue(all('continue-on-error' not in step for step in job['steps']))

    def test_original_check_explicitly_fails_for_every_non_success_laya_result(self):
        for name in ['ci', 'verify']:
            with self.subTest(workflow=name):
                jobs = yaml.load((ROOT / f'.github/workflows/{name}.yml').read_text(), Loader=yaml.BaseLoader)['jobs']
                original = jobs[name]
                self.assertEqual(original.get('needs'), ['laya-offline'])
                self.assertEqual(original.get('if'), '${{ always() }}')
                guards = [step for step in original['steps'] if step.get('name') == 'Require independent Laya success']
                self.assertEqual(len(guards), 1)
                guard = guards[0]
                self.assertEqual(guard.get('if'), '${{ always() }}')
                self.assertEqual(guard.get('env'), {'LAYA_RESULT': "${{ needs['laya-offline'].result }}"})
                self.assertLess(original['steps'].index(guard), next(i for i, step in enumerate(original['steps']) if 'flutter-action' in step.get('uses', '')))
                self.assertNotIn('continue-on-error', original)
                self.assertNotIn('continue-on-error', guard)
                for result in ['success', 'failure', 'cancelled', 'skipped', '', 'unknown']:
                    with self.subTest(result=result):
                        observed = subprocess.run(['bash', '-e', '-c', guard['run']], env={**os.environ, 'LAYA_RESULT': result}, capture_output=True)
                        self.assertEqual(observed.returncode == 0, result == 'success')

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
            before = yaml.load(subprocess.check_output(['git', 'show', f'{GATE_BASE}:.github/workflows/{name}.yml'], cwd=ROOT, text=True), Loader=yaml.BaseLoader)
            after = yaml.load((ROOT / f'.github/workflows/{name}.yml').read_text(), Loader=yaml.BaseLoader)
            self.assertEqual(before['on'], after['on'])
            for key, job in before['jobs'].items():
                job['steps'] = [s for s in job['steps'] if not s.get('name', '').startswith('Laya script tests')]
                observed = dict(after['jobs'][key])
                observed.pop('needs', None)
                observed.pop('if', None)
                observed['steps'] = [step for step in observed['steps'] if step.get('name') != 'Require independent Laya success']
                self.assertEqual(job, observed, 'coverage/analyze/test/artifact configuration must stay intact')
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
    def test_root_toolchain_is_covered_without_changing_original_product_jobs(self):
        path = '.github/workflows/muyon-product.yml'
        previous = subprocess.check_output(['git', 'show', SOURCE_PIN + ':' + path], cwd=ROOT)
        current = (ROOT / path).read_bytes()
        self.assertTrue((ROOT / 'rust-toolchain.toml').is_file())
        self.assertTrue(product_gate_matches_historical(previous, current, True))
        self.assertTrue(product_gate_matches_historical(previous, previous, False))
        self.assertFalse(product_gate_matches_historical(previous, previous, True),
                         'a root toolchain input must not silently skip the product gate')

    def test_product_gate_witness_rejects_unreviewed_changes(self):
        path = '.github/workflows/muyon-product.yml'
        previous = subprocess.check_output(['git', 'show', SOURCE_PIN + ':' + path], cwd=ROOT)
        anchor = b'    paths: &product_paths\n'
        entry = b"      - 'rust-toolchain.toml'\n"
        expected = previous.replace(anchor, anchor + entry, 1)
        mutations = {
            'missing root path': expected.replace(entry, b'', 1),
            'duplicate root path': expected.replace(entry, entry + entry, 1),
            'broader permission': expected.replace(b'contents: read', b'contents: write', 1),
            'weaker clippy': expected.replace(b'-D warnings', b'-A warnings', 1),
            'changed aggregate': expected.replace(b'  required-product:', b'  optional-product:', 1),
            'changed model check': expected.replace(b'model_package_gate.py', b'no_model_gate.py', 1),
            'missing Rust path': expected.replace(b"      - 'crates/**'\n", b'', 1),
        }
        for label, changed in mutations.items():
            with self.subTest(mutation=label):
                self.assertNotEqual(changed, expected, 'mutation must actually change its target')
                self.assertFalse(product_gate_matches_historical(previous, changed, True))

    def test_historical_manifest_cannot_remove_all_references(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            paths = ['scripts/test_retirement_prerequisites.py', 'docs/legacy/flutter-source-manifest.json',
                     'crates/muyon-core/Cargo.toml', '.github/workflows/muyon-product.yml',
                     'apps/muyon_android/prepare-model-assets.py', 'scripts/coverage/baseline.json']
            for relative in paths:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            common = subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=ROOT, text=True).strip()
            objects = (ROOT / common / 'objects').resolve()
            (root / '.git/objects/info/alternates').write_text(str(objects) + '\n')
            manifest_path = root / 'docs/legacy/flutter-source-manifest.json'
            manifest = json.loads(manifest_path.read_text())
            manifest['references'] = []
            manifest_path.write_text(json.dumps(manifest))
            result = subprocess.run([sys.executable, '-B', str(root / 'scripts/test_retirement_prerequisites.py'),
                                     'FrozenSchema.test_historical_reference_manifest_matches_fixed_git_objects'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('FAIL', result.stderr)

    def invoke_checker(self, directory):
        return subprocess.run([sys.executable, '-B', str(ROOT / 'scripts/check_legacy_schema_reference.py'), str(directory)], capture_output=True, text=True)

    def test_fixed_witness_rejects_synchronized_fixture_and_manifest_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / 'fixture'
            shutil.copytree(FIXTURE, directory)
            self.assertEqual(self.invoke_checker(directory).returncode, 0)
            data = (directory / 'store.dart').read_bytes() + b'\n// synchronized replacement\n'
            (directory / 'store.dart').write_bytes(data)
            manifest = json.loads((directory / 'manifest.json').read_text())
            entry = manifest['files']['store.dart']
            entry.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                         git_blob=hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest())
            (directory / 'manifest.json').write_text(json.dumps(manifest))
            self.assertNotEqual(self.invoke_checker(directory).returncode, 0)

    def test_fixed_witness_rejects_manifest_blob_mutations(self):
        for name in ['store.dart', 'entities.dart']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp) / 'fixture'
                shutil.copytree(FIXTURE, directory)
                manifest = json.loads((directory / 'manifest.json').read_text())
                manifest['files'][name]['git_blob'] = '0' * 40
                (directory / 'manifest.json').write_text(json.dumps(manifest))
                self.assertNotEqual(self.invoke_checker(directory).returncode, 0)

    def test_checker_rejects_missing_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / 'fixture'
            shutil.copytree(FIXTURE, directory)
            (directory / 'manifest.json').unlink()
            self.assertNotEqual(self.invoke_checker(directory).returncode, 0)

    def test_missing_history_is_failure_not_a_silent_skip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'scripts').mkdir()
            shutil.copyfile(Path(__file__), root / 'scripts/test_retirement_prerequisites.py')
            shutil.copytree(FIXTURE, root / FIXTURE.relative_to(ROOT))
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            result = subprocess.run([sys.executable, '-B', str(root / 'scripts/test_retirement_prerequisites.py'),
                                     'FrozenSchema.test_exact_historical_source_bytes_are_preserved'], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('git', result.stderr)
            self.assertNotIn('skipped', result.stderr.lower())

    def manifest(self):
        file = FIXTURE / 'manifest.json'
        self.assertTrue(file.is_file(), 'frozen reference manifest is missing')
        return json.loads(file.read_text())

    def test_exact_historical_source_bytes_are_preserved(self):
        data = self.manifest()
        self.assertEqual(data['source_sha'], SOURCE_PIN)
        self.assertEqual(set(data['files']), {'store.dart', 'entities.dart'})
        for name, entry in data['files'].items():
            historical = subprocess.check_output(['git', 'show', f'{SOURCE_PIN}:{entry["source_path"]}'], cwd=ROOT)
            self.assertEqual((FIXTURE / name).read_bytes(), historical)
            self.assertEqual(entry['sha256'], hashlib.sha256(historical).hexdigest())

    def test_rust_test_consumes_frozen_reference_without_removing_assertions(self):
        path = ROOT / 'experiments/redesign/rust-agent-host-lab/core/tests/supplier_store.rs'
        source = path.read_text()
        self.assertNotIn('include_str!("../../../../../packages/', source)
        self.assertIn('include_str!("fixtures/legacy-schema12/store.dart")', source)
        self.assertIn('include_str!("fixtures/legacy-schema12/entities.dart")', source)
        previous = subprocess.check_output(['git', 'show', f'{SOURCE_PIN}:{path.relative_to(ROOT)}'], cwd=ROOT, text=True)
        expected = previous.replace('../../../../../packages/supplier_core/lib/src/', 'fixtures/legacy-schema12/')
        self.assertEqual(source, expected, 'only include paths change; all real Rust assertions remain')

    def test_historical_reference_manifest_matches_fixed_git_objects(self):
        path = ROOT / 'docs/legacy/flutter-source-manifest.json'
        self.assertTrue(path.is_file(), 'historical source references are not fixed yet')
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), SOURCE_MANIFEST_SHA256,
                         'immutable reference inventory cannot redefine its own witnesses')
        manifest = json.loads(path.read_text())
        self.assertEqual(manifest['legacy_source_sha'], SOURCE_PIN)
        self.assertEqual(manifest['legacy_ci']['status'], 'FAILED')
        for entry in manifest['references']:
            source = subprocess.check_output(['git', 'show', entry['source_sha'] + ':' + entry['source_path']], cwd=ROOT)
            self.assertEqual(hashlib.sha256(source).hexdigest(), entry['sha256'])
            self.assertEqual(len(source), entry['bytes'])
            blob = subprocess.check_output(['git', 'rev-parse', entry['source_sha'] + ':' + entry['source_path']], cwd=ROOT, text=True).strip()
            self.assertEqual(blob, entry['git_blob'])
        for path in ['crates/muyon-core/Cargo.toml', '.github/workflows/muyon-product.yml',
                     'apps/muyon_android/prepare-model-assets.py', 'scripts/coverage/baseline.json']:
            previous = subprocess.check_output(['git', 'show', SOURCE_PIN + ':' + path], cwd=ROOT)
            current = (ROOT / path).read_bytes()
            if path == '.github/workflows/muyon-product.yml':
                self.assertTrue(product_gate_matches_historical(
                    previous, current, (ROOT / 'rust-toolchain.toml').is_file()),
                    'only the root-toolchain path may extend the frozen product gate')
            else:
                self.assertEqual(current, previous)

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
