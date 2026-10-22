"""Repeat three safety/reporting mutations against ephemeral source copies only."""
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    source = (root / 'harness.py').read_text()
    tests = (root / 'tests/test_harness.py').read_text()
    generator = (root / 'generate_fixtures.py').read_text()
    cases = {
        'unsafe_path_disabled': ('if unsafe_path(name):', 'if False:'),
        'unknown_part_loss_ignored': (
            "if a['decision'] == 'reject' or b['decision'] == 'reject' or missing or changed:",
            "if a['decision'] == 'reject' or b['decision'] == 'reject' or changed:"),
        'false_render_success': (
            "for key in ('structure', 'visual', 'formula', 'annotation', 'render', 'recalc')})",
            "for key in ('structure', 'visual', 'formula', 'annotation', 'render', 'recalc')})\n    report['dimensions']['render']['status'] = 'pass'"),
    }
    for name, (old, new) in cases.items():
        assert old in source, name
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            package = base / 'tools/document_fidelity'
            (package / 'tests').mkdir(parents=True)
            (package / 'harness.py').write_text(source.replace(old, new, 1))
            (package / 'generate_fixtures.py').write_text(generator)
            (package / 'tests/test_harness.py').write_text(tests)
            result = subprocess.run(
                [sys.executable, '-m', 'unittest', 'discover', '-s', 'tools/document_fidelity/tests', '-v'],
                cwd=base, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            print(name, 'exit=', result.returncode, 'KILLED' if result.returncode else 'SURVIVED')
            print(result.stdout)
            assert result.returncode != 0, name
    print('3/3 mutations killed. Only ephemeral copies changed; original fixtures/source untouched.')


if __name__ == '__main__':
    main()
