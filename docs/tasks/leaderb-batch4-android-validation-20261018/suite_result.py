"""Fail-closed aggregation shared by the actual suite and subprocess controls."""
import json
from pathlib import Path
import sys

REQUIRED = {'arm64-v8a','x86_64','linux','service','service-inverses','service-private','package','ordinary','controls','verification-controls'}

def outcome(rows):
    names=[row['stage'] for row in rows]
    missing=sorted(REQUIRED-set(names))
    duplicate=sorted({name for name in names if names.count(name)!=1})
    failed=[row for row in rows if row.get('exit')!=0]
    accepted=not missing and not duplicate and not failed and set(names)==REQUIRED
    return dict(classification='GREEN' if accepted else 'INVALID',accepted=accepted,missing_stages=missing,duplicate_stages=duplicate,failed_stages=failed)

if __name__=='__main__':
    verdict=outcome(json.loads(Path(sys.argv[1]).read_text()))
    print(json.dumps(verdict,sort_keys=True))
    raise SystemExit(0 if verdict['accepted'] else 1)
