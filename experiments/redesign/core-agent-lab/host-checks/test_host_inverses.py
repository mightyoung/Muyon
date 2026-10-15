"""Inverse runner classifier/copy checks; these are not DUT mutation evidence."""
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import unittest

from host_inverses import classify, copy_sources, diagnostic_excerpt, events


def observation(*, failure=True, marker='HOST_BOUNDARY', is_failure=True):
    rows = [{'type': 'testStart', 'test': {'id': 2, 'name': 'exact target'}}]
    if failure:
        rows.append({'type': 'error', 'testID': 2, 'isFailure': is_failure, 'error': marker})
    rows.extend([
        {'type': 'testDone', 'testID': 2, 'result': 'failure' if failure else 'success', 'skipped': False},
        {'type': 'done', 'success': not failure},
    ])
    return rows


class InverseRunnerTests(unittest.TestCase):
    def test_reporter_events_read_exact_json_and_reject_malformed_files(self):
        with TemporaryDirectory(prefix='host-reporter-check-') as temporary:
            path = Path(temporary) / 'report.jsonl'
            self.assertEqual(events(path), [])
            path.write_text(json.dumps({'type': 'done', 'success': True}) + '\n')
            self.assertEqual(events(path), [{'type': 'done', 'success': True}])
            path.write_text('compiler diagnostic, not reporter JSON\n')
            self.assertEqual(events(path), [])

    def test_failed_baseline_diagnostic_is_bounded_and_redacts_synthetic_canaries(self):
        text = 'setup failed sk-HOST_AUTH_CANARY_460a HOST_PROFILE_95c1 PRIVATE_HOST_NOTES_c391\n' + ('x' * 500 + '\n') * 100
        excerpt = diagnostic_excerpt(text)
        self.assertLessEqual(len(excerpt), 8000)
        self.assertIn('setup failed', excerpt)
        self.assertNotIn('sk-HOST_AUTH_CANARY_460a', excerpt)
        self.assertNotIn('HOST_PROFILE_95c1', excerpt)
        self.assertNotIn('PRIVATE_HOST_NOTES_c391', excerpt)

    def test_only_compiled_single_target_matcher_failure_is_accepted(self):
        self.assertTrue(classify(observation(), 1, 'exact target', 'HOST_BOUNDARY')['accepted'])
        cases = [
            ([], 1),  # compile error / absent reporter is never a kill
            (observation(is_failure=False), 1),  # timeout/exception
            (observation(marker='OTHER_BOUNDARY'), 1),
            (observation(), 0),
            (observation(), 124),
            (observation(failure=False), 0),
            (observation() + [{'type': 'error', 'testID': 2, 'error': 'teardown', 'isFailure': False}], 1),
            (observation() + [{'type': 'testDone', 'testID': 3, 'result': 'failure'}], 1),
        ]
        for rows, exit_code in cases:
            with self.subTest(rows=rows, exit_code=exit_code):
                self.assertFalse(classify(rows, exit_code, 'exact target', 'HOST_BOUNDARY')['accepted'])

    def test_baseline_requires_successful_unskipped_same_target(self):
        self.assertTrue(classify(observation(failure=False), 0, 'exact target')['accepted'])
        self.assertFalse(classify(observation(), 1, 'exact target')['accepted'])
        self.assertFalse(classify(observation(failure=False), 0, 'wrong target')['accepted'])
        skipped = observation(failure=False)
        skipped[-2]['skipped'] = True
        self.assertFalse(classify(skipped, 0, 'exact target')['accepted'])

    def test_copy_remaps_both_relative_and_absolute_dut_packages(self):
        with TemporaryDirectory(prefix='host-inverse-copier-check-') as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            (source / 'apps/muyon').mkdir(parents=True)
            (source / 'apps/muyon/pubspec.yaml').write_text('name: muyon\n')
            subprocess.run(['git', '-C', str(source), 'add', '.'], check=True)
            (source / '.dart_tool').mkdir()
            for uri in ['../apps/muyon', (source / 'apps/muyon').as_uri()]:
                config = {'configVersion': 2, 'packages': [
                    {'name': 'muyon', 'rootUri': uri, 'packageUri': 'lib/'},
                    {'name': 'external', 'rootUri': '../../external', 'packageUri': 'lib/'},
                ]}
                (source / '.dart_tool/package_config.json').write_text(json.dumps(config))
                destination = root / ('relative-copy' if uri.startswith('..') else 'absolute-copy')
                copy_sources(source, destination)
                copied = json.loads((destination / '.dart_tool/package_config.json').read_text())
                self.assertEqual(copied['packages'][0]['rootUri'], (destination / 'apps/muyon').as_uri())
                self.assertEqual(copied['packages'][1]['rootUri'], (root / 'external').as_uri())
                self.assertTrue((destination / 'apps/muyon/pubspec.yaml').is_file())
                self.assertFalse((destination / '.git').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
