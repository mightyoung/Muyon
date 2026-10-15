#!/usr/bin/python3
"""Transparent test-only launcher: real child bytes are never rewritten."""
import argparse
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', required=True)
    parser.add_argument('--evidence', required=True)
    options, arguments = parser.parse_known_args()
    evidence = Path(options.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    child = subprocess.Popen([options.binary, *arguments], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (evidence / 'launch.json').write_text(json.dumps({
        'pid': child.pid, 'binary': options.binary, 'arguments': arguments,
        'environment_keys': sorted(os.environ),
    }))

    def stop(signum, frame):
        if child.poll() is None:
            child.terminate()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin.buffer, selectors.EVENT_READ, 'input')
    selector.register(child.stdout, selectors.EVENT_READ, 'output')
    selector.register(child.stderr, selectors.EVENT_READ, 'error')
    outputs = {'input': (evidence / 'host.bin').open('wb'),
               'output': (evidence / 'core.bin').open('wb'),
               'error': (evidence / 'stderr.bin').open('wb')}
    try:
        while selector.get_map():
            for key, _ in selector.select(timeout=0.1):
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    if key.data == 'input':
                        child.stdin.close()
                    continue
                outputs[key.data].write(data)
                outputs[key.data].flush()
                if key.data == 'input':
                    try:
                        child.stdin.write(data)
                        child.stdin.flush()
                    except BrokenPipeError:
                        selector.unregister(key.fileobj)
                elif key.data == 'output':
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                else:
                    sys.stderr.buffer.write(data)
                    sys.stderr.buffer.flush()
            if child.poll() is not None:
                for key in list(selector.get_map().values()):
                    if key.data == 'input':
                        selector.unregister(key.fileobj)
        code = child.wait(timeout=5)
    finally:
        if child.poll() is None:
            child.kill()
        code = child.wait(timeout=5)
        for stream in outputs.values():
            stream.close()
        selector.close()
        (evidence / 'exit.json').write_text(json.dumps({'code': code, 'reaped': True}))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
