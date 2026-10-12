import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    'evidence', Path(__file__).with_name('linux_verification_evidence.py'))
evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sha = 'a' * 40
        self.request = {
            'candidate_sha': self.sha,
            'system': {'os': 'Linux', 'release': '6.8.0', 'architecture': 'x86_64'},
            'flutter_version': 'Flutter 3.35.4', 'dart_version': 'Dart 3.9.2',
            'stages': {},
        }

    def stage(self, name, code=0, cases=('smoke',)):
        log = self.root / (name + '.log')
        rows = [dict(evidence_version=1, candidate_sha=self.sha, stage=name,
                     case_id=case, outcome='passed') for case in cases]
        log.write_text('\n'.join(json.dumps(row) for row in rows), encoding='utf-8')
        self.request['stages'][name] = {
            'log': str(log), 'exit_code': code,
            'command': ['flutter', 'test', '/home/CANARY_USER/private',
                        '--token=CANARY_SECRET', 'https://CANARY_ENDPOINT'],
            'started_at': '2026-10-12T01:00:00Z',
            'ended_at': '2026-10-12T01:01:00Z', 'expected_cases': list(cases),
        }
        return log

    def collect(self):
        return evidence.collect(self.request, self.root)

    def test_missing_inputs_are_unknown(self):
        manifest, summary = self.collect()
        self.assertTrue(all(s['status'] == 'unknown' for s in manifest['stages'].values()))
        self.assertIn('unknown', summary)

    def test_all_four_phases_need_separate_evidence(self):
        for name in evidence.STAGES:
            self.stage(name)
        manifest, summary = self.collect()
        self.assertTrue(all(s['status'] == 'passed' for s in manifest['stages'].values()))
        self.assertIn('交互：passed', summary)

    def test_exit_zero_and_plain_log_do_not_prove_interaction(self):
        log = self.stage('linux_interaction')
        log.write_text('exit 0\nAll tests passed!\n', encoding='utf-8')
        self.assertEqual(self.collect()[0]['stages']['linux_interaction']['status'], 'unknown')

    def test_interaction_needs_launch(self):
        self.stage('linux_interaction')
        self.assertEqual(self.collect()[0]['stages']['linux_interaction']['status'], 'unknown')

    def test_failed_exit_wins_over_pass_marker(self):
        self.stage('unit_widget', code=1)
        self.assertEqual(self.collect()[0]['stages']['unit_widget']['status'], 'failed')

    def test_partial_cases_and_wrong_sha_are_unknown(self):
        log = self.stage('unit_widget')
        self.request['stages']['unit_widget']['expected_cases'].append('second')
        self.assertEqual(self.collect()[0]['stages']['unit_widget']['status'], 'unknown')
        self.request['stages']['unit_widget']['expected_cases'] = ['smoke']
        log.write_text(log.read_text().replace(self.sha, 'b' * 40))
        self.assertEqual(self.collect()[0]['stages']['unit_widget']['status'], 'unknown')

    def test_conflicting_marker_does_not_pass(self):
        log = self.stage('unit_widget')
        with log.open('a') as stream:
            stream.write('\n' + json.dumps(dict(evidence_version=1, candidate_sha=self.sha,
                stage='unit_widget', case_id='smoke', outcome='failed')))
        self.assertEqual(self.collect()[0]['stages']['unit_widget']['status'], 'failed')

    def test_hashes_exact_bytes_without_copying_raw_log_or_secrets(self):
        log = self.stage('unit_widget')
        with log.open('a') as stream:
            stream.write('\nCANARY_SECRET https://CANARY_ENDPOINT /home/CANARY_USER/private\n')
        manifest, summary = self.collect()
        stage = manifest['stages']['unit_widget']
        self.assertEqual(stage['log_sha256'], hashlib.sha256(log.read_bytes()).hexdigest())
        self.assertEqual(stage['log_bytes'], len(log.read_bytes()))
        exported = json.dumps(manifest) + summary
        self.assertNotIn('CANARY', exported)
        self.assertNotIn(str(self.root), exported)
        self.assertNotIn('https://', exported)
        self.assertNotIn('/home/', exported)
        self.assertIn('command_sha256', stage)

    def test_missing_log_failed_exit_and_missing_metadata(self):
        log = self.stage('linux_build')
        log.unlink()
        self.assertEqual(self.collect()[0]['stages']['linux_build']['status'], 'unknown')
        self.request['stages']['linux_build']['exit_code'] = 2
        self.assertEqual(self.collect()[0]['stages']['linux_build']['status'], 'failed')
        self.stage('linux_build')
        del self.request['stages']['linux_build']['started_at']
        self.assertEqual(self.collect()[0]['stages']['linux_build']['status'], 'unknown')

    def test_credentials_rejected_without_reading(self):
        self.stage('unit_widget')
        for name in ('.env', '.env.production', 'credentials.json', 'id_rsa'):
            self.request['stages']['unit_widget']['log'] = str(self.root / name)
            self.assertEqual(self.collect()[0]['stages']['unit_widget']['error_code'], 'input_forbidden')

    def test_invalid_identity_and_stage_are_rejected(self):
        self.request['candidate_sha'] = 'secret/path'
        with self.assertRaises(ValueError):
            self.collect()
        self.request['candidate_sha'] = self.sha
        self.request['stages']['unexpected'] = {}
        with self.assertRaises(ValueError):
            self.collect()

    def test_versions_and_non_linux_are_conservative(self):
        self.stage('unit_widget')
        self.request['system']['os'] = 'Darwin CANARY_SECRET'
        self.request['flutter_version'] = 'CANARY_SECRET'
        manifest, summary = self.collect()
        self.assertEqual(manifest['system']['os'], 'unknown')
        self.assertEqual(manifest['flutter_version'], 'unknown')
        self.assertEqual(manifest['stages']['unit_widget']['status'], 'unknown')
        self.assertNotIn('CANARY', json.dumps(manifest) + summary)

    def test_bad_time_and_exit_type_are_unknown_and_input_unchanged(self):
        self.stage('unit_widget')
        self.request['stages']['unit_widget']['ended_at'] = '2020-01-01T00:00:00Z'
        original = copy.deepcopy(self.request)
        self.assertEqual(self.collect()[0]['stages']['unit_widget']['status'], 'unknown')
        self.assertEqual(self.request, original)
        self.request['stages']['unit_widget']['exit_code'] = False
        self.assertEqual(self.collect()[0]['stages']['unit_widget']['status'], 'unknown')


if __name__ == '__main__':
    unittest.main()
