#!/usr/bin/env python3
"""Verify fixed host pure consumer and unchanged shell memory controller. No Service/native execution."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
FIXED = '9d2c4119d0c66d1748955cee1d86e63deb7ce16f'
COMPILER = '/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc'
JSON_JAR = '/workspace/ui-shell-tools/json-20250517.jar'
PREFIX = 'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/'
FILES = ['agents/setup/BotSetupDraft.kt', 'agents/setup/SetupDraftArchive.kt',
         'chat/persistence/HostDraftSaveState.kt', 'chat/persistence/NativeLocalDraftCodec.kt',
         'chat/ProductChatRuntime.kt', 'chat/ProductSendGate.kt', 'chat/ProductHttpsTransport.kt',
         'chat/persistence/HostLocalDraftSession.kt']
TESTS = 'apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/'
with tempfile.TemporaryDirectory(prefix='muyon-host-9d2c-') as temp:
    folder = Path(temp)
    inputs = []
    hashes = {}
    for file in FILES + ['TEST:chat/persistence/HostLocalDraftSessionChecks.kt']:
        path = TESTS + file[5:] if file.startswith('TEST:') else PREFIX + file
        raw = subprocess.check_output(['git', 'show', f'{FIXED}:{path}'], cwd=ROOT)
        target = folder / Path(path).name
        target.write_bytes(raw)
        hashes[f'{FIXED}:{path}'] = hashlib.sha256(raw).hexdigest()
        inputs.append(str(target))
    for path in [PREFIX + 'ui/shell/HostSetupController.kt', TESTS + 'ui/shell/HostSetupControllerChecks.kt']:
        raw = (ROOT / path).read_bytes()
        target = folder / Path(path).name
        target.write_bytes(raw)
        hashes[f'shell:{path}'] = hashlib.sha256(raw).hexdigest()
        inputs.append(str(target))
    command = [COMPILER, '-Werror', '-jvm-target', '17', '-classpath', JSON_JAR] + inputs + ['-include-runtime', '-d', str(folder / 'checks.jar')]
    compiled = subprocess.run(command, capture_output=True, text=True)
    output = f'fixed_host={FIXED}\ncommand={json.dumps(command)}\nsources={json.dumps(hashes)}\ncompile_exit={compiled.returncode}\n' + compiled.stdout + compiled.stderr
    results = []
    if compiled.returncode == 0:
        for main in ['com.mightyoung.muyon.product.chat.persistence.HostLocalDraftSessionChecksKt',
                     'com.mightyoung.muyon.product.ui.shell.HostSetupControllerChecksKt']:
            run = subprocess.run(['java', '-cp', f'{folder / "checks.jar"}:{JSON_JAR}', main], capture_output=True, text=True)
            output += f'main={main}\nrunner_exit={run.returncode}\n' + run.stdout + run.stderr
            results.append(run.returncode)
    (OUT / 'host-9d2c-compatibility.log').write_text(output)
    print(output)
    assert compiled.returncode == 0 and results == [0, 0]
