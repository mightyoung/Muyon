"""Resolve existing cache only, without adding or downloading dependencies."""
import json
import os
from pathlib import Path
import sys

cache = Path(os.environ.get('PUB_CACHE', str(Path.home() / '.pub-cache'))) / 'hosted/pub.dev'
packages = []
for name, version in [('archive', '4.0.9'), ('path', '1.9.1'), ('posix', '6.5.2')]:
    root = cache / f'{name}-{version}'
    if not root.is_dir():
        raise SystemExit(f'Required existing cache unavailable: {name}-{version}')
    packages.append({'name': name, 'rootUri': root.as_uri() + '/', 'packageUri': 'lib/', 'languageVersion': '3.0'})
Path(sys.argv[1]).write_text(json.dumps({'configVersion': 2, 'packages': packages}))
