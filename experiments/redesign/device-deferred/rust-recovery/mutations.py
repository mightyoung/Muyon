"""Scoped inverse mutations; restores source even on failure. Raw logs outside git."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
source = root / 'src/lib.rs'
original = source.read_bytes()
output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
mutations = [
    ('wrong_domain', 'if event.cursor.domain != self.applied.domain', 'if false', 'all_three_domain_fields_are_required'),
    ('epoch_erases_receipts', 'self.epoch=epoch;', 'self.epoch=epoch; self.receipts.clear();', 'epoch_is_only_display_fence'),
    ('new_intent_erases_unknown', 'self.synthetic_intents.insert(new.intent.clone(),new);', 'self.unknown.remove(old); self.synthetic_intents.insert(new.intent.clone(),new);', 'unknown_survives_reconnect_and_new_intent'),
]
results = []
try:
    for name, before, after, test in mutations:
        text = original.decode()
        assert text.count(before) == 1
        source.write_text(text.replace(before, after))
        result = subprocess.run(['cargo', 'test', '--offline', '--manifest-path', str(root/'Cargo.toml'), test, '--', '--exact'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (output / (name+'.log')).write_bytes(result.stdout)
        assertion_failed = b'assertion' in result.stdout and b'FAILED' in result.stdout
        results.append({'name':name, 'test':test, 'exit':result.returncode, 'assertion_failed':assertion_failed})
        assert result.returncode == 101 and assertion_failed, results[-1]
finally:
    source.write_bytes(original)
restored = hashlib.sha256(source.read_bytes()).hexdigest()
assert source.read_bytes() == original
report = {'source_sha256':restored, 'restored':True, 'mutations':results}
(output/'mutations.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
