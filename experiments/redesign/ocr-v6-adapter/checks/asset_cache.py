"""Fetch only immutable, hash-locked OCR assets into a caller-owned external cache."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def fetch(cache):
    lock = json.loads((ROOT / 'models.lock.json').read_text())
    for model in lock['models']:
        for item in model['files']:
            target = cache / model['repository'].split('/')[1] / item['file']
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                data = target.read_bytes()
                if len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256']:
                    continue
            with urllib.request.urlopen(item['url'], timeout=90) as response:
                data = response.read(item['bytes'] + 1)
            if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
                raise ValueError('Asset verification failed: ' + model['repository'] + '/' + item['file'])
            temporary = target.with_suffix(target.suffix + '.part')
            temporary.write_bytes(data)
            temporary.replace(target)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('cache', type=Path)
    args = parser.parse_args()
    cache = args.cache.resolve()
    if cache.is_relative_to(ROOT):
        parser.error('Model cache must be outside the source module')
    fetch(cache)
    print('All four v6 det/rec model and config bundles match models.lock.json')
