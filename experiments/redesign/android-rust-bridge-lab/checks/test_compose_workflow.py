"""Plain no-native Compose workflow controls, not Android runtime evidence."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

WORKFLOW = Path(__file__).resolve().parents[4] / '.github/workflows/android-compose-lab.yml'


def required_script():
    section = WORKFLOW.read_text().split('      - name: Required JVM checks and Android source compilation\n', 1)[1]
    code = section.split('        run: |\n', 1)[1].split('      - name:', 1)[0]
    return '\n'.join(line[10:] for line in code.splitlines()) + '\n'


class ComposeWorkflowControls(unittest.TestCase):
    def test_plain_apk_requires_unit_source_compile_and_min24_lint(self):
        script = required_script()
        for task in [':state:check', ':app:assembleDebug', ':app:assembleDebugAndroidTest',
                     ':app:compileDebugUnitTestKotlin', ':app:lintDebug']:
            self.assertEqual(script.split().count(task), 1)
        self.assertNotIn('-PmuyonBridge', script)
        self.assertIn('Rust integration runtime=NOT_RUN', WORKFLOW.read_text())
        self.assertNotIn('Rust integration=NOT_CONNECTED', WORKFLOW.read_text())
        for exit_code in [0, 9]:
            with tempfile.TemporaryDirectory(prefix='compose-workflow-control-') as tmp:
                root=Path(tmp); tools=root/'muyon-compose-tools/gradle-8.13/bin';tools.mkdir(parents=True)
                gradle=tools/'gradle'
                gradle.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$ARGUMENT_LOG"\nprintf "%s\\n" "16/16 pure JVM state checks passed" "22/22 local UI state checks passed"\nexit "$CONTROL_EXIT"\n')
                gradle.chmod(0o700); logs=root/'logs';logs.mkdir()
                result=subprocess.run(['bash','-c',script],capture_output=True,timeout=5,
                    env=dict(os.environ,RUNNER_TEMP=str(root),LAB_DIRECTORY='synthetic-lab',
                             GRADLE_VERSION='8.13',LOG_DIRECTORY=str(logs),
                             ARGUMENT_LOG=str(root/'args'),CONTROL_EXIT=str(exit_code)))
                self.assertEqual(result.returncode,exit_code,result.stderr)
                args=(root/'args').read_text().splitlines()
                self.assertIn(':app:compileDebugUnitTestKotlin',args)
                self.assertIn(':app:lintDebug',args)
                self.assertIn('required_exit='+str(exit_code),(logs/'required-exit.txt').read_text())


if __name__=='__main__':
    unittest.main()
