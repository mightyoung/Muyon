#!/usr/bin/env python3
"""Temporarily bypass pending per channel; restore source even after failure."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = root / 'apps/muyon/lib/platform/outbound_tool_ledger.dart'
original = source.read_text()
evidence = root / 'docs/verification/REG-2a'
env = dict(os.environ)
for key in ('http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'all_proxy'):
    env.pop(key, None)
env['NO_PROXY'] = 'localhost,127.0.0.1,::1'
results = []
try:
    for channel in ('mcp', 'inquiry_web', 'inquiry_hub', 'transfer'):
        # Bypasses begin AND finish for precisely this real channel, while
        # retaining all registry approval/receipt code and real transports.
        mutant = original.replace('    final id = await begin(',
            f"    if (channel == '{channel}') return operation((_) {{}});\n    final id = await begin(", 1)
        assert mutant != original
        source.write_text(mutant)
        log = evidence / f'mutation-{channel}.log'
        with log.open('w') as out:
            command = ['flutter', 'test', '--no-pub', 'test/outbound_tool_ledger_test.dart',
                '--plain-name', f'{channel} blocked ledger sends zero requests', '--reporter', 'expanded']
            result = subprocess.run(command, cwd=root / 'apps/muyon', env=env,
                stdout=out, stderr=subprocess.STDOUT)
            out.write(f'\nEXIT_CODE={result.returncode}\n')
        text = log.read_text()
        killed = result.returncode != 0 and f'REG2A_BLOCKED {channel} requests=' in text and f'REG2A_BLOCKED {channel} requests=0' not in text and 'Some tests failed.' in text
        results.append(f'{channel}: EXIT_CODE={result.returncode} KILLED={str(killed).lower()}')
        print(results[-1], flush=True)
        source.write_text(original)
finally:
    source.write_text(original)
(evidence / 'mutation-summary.log').write_text('\n'.join(results) + '\n')
if not all('KILLED=true' in row for row in results) or len(results) != 4:
    raise SystemExit('Mutation did not fail for the expected missing ledger reason')
