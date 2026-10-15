#!/usr/bin/env python3
"""Trusted offline service fixture. Capture actual stdin before any SSE emission.

No socket/client/credential access. Configuration describes input bytes or an
answer transformation of the actual received tool content, never a DUT oracle.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import sys


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate fixture/request key')
        result[key] = value
    return result


def emitted_answer(request):
    messages = request['messages']
    tool = next(message for message in reversed(messages) if message.get('role') == 'tool')
    content = json.loads(tool['content'], object_pairs_hook=unique)
    if type(content.get('value')) is not str or type(content.get('receipt')) is not str:
        raise ValueError('received tool content has no value/receipt')
    return json.dumps({'value': content['value'], 'receipt': content['receipt']}, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def encode_answer(text):
    def event(value):
        return ('data: ' + json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n\n').encode()
    return (event({'choices': [{'index': 0, 'delta': {'content': text}}]}) +
            event({'choices': [{'index': 0, 'delta': {}, 'finish_reason': 'stop'}]}) +
            b'data: [DONE]\n\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture-dir', type=Path, required=True)
    parser.add_argument('--turn', type=int, required=True)
    parser.add_argument('--capture-dir', type=Path, required=True)
    args = parser.parse_args()
    config = json.loads((args.fixture_dir / 'config.json').read_text(), object_pairs_hook=unique)
    if set(config) != {'format', 'turns'} or config['format'] != 'core-wire-service-v1':
        raise ValueError('unsupported service fixture')
    if not 1 <= args.turn <= len(config['turns']):
        raise ValueError('no scripted response for admitted turn')
    turn = config['turns'][args.turn - 1]
    if set(turn) - {'response', 'answer_from_tool', 'exit_code', 'stderr', 'hold'}:
        raise ValueError('unknown service fixture field')
    if ('response' in turn) == ('answer_from_tool' in turn):
        raise ValueError('choose raw input or received-tool transformation')
    if 'hold' in turn and turn['hold'] not in {'before_stdin', 'silent', 'after_eof'}:
        raise ValueError('unknown fixture hold')
    args.capture_dir.mkdir(parents=True, exist_ok=True)
    (args.capture_dir / f'child-{args.turn}.pid').write_text(str(os.getpid()) + '\n')
    if turn.get('hold') == 'before_stdin':
        signal.pause()
        return
    request = sys.stdin.buffer.read(65537)
    if len(request) > 65536:
        raise ValueError('request cap exceeded at service')
    # Exclusive capture: repeated admission cannot overwrite earlier evidence.
    with (args.capture_dir / f'request-{args.turn}.json').open('xb') as capture:
        capture.write(request)
        capture.flush()
        os.fsync(capture.fileno())
    if turn.get('hold') == 'silent':
        signal.pause()
        return
    if 'response' in turn:
        response_path = args.fixture_dir / turn['response']
        if response_path.parent.resolve() != args.fixture_dir.resolve():
            raise ValueError('fixture response path must be local')
        response = response_path.read_bytes()
    else:
        parsed = json.loads(request.decode('utf-8'), object_pairs_hook=unique)
        response = encode_answer(emitted_answer(parsed))
    (args.capture_dir / f'emitted-{args.turn}.sse').write_bytes(response)
    sys.stdout.buffer.write(response)
    sys.stdout.buffer.flush()
    if turn.get('hold') == 'after_eof':
        os.close(sys.stdout.fileno())
        signal.pause()
        return
    if turn.get('stderr'):
        print(turn['stderr'], file=sys.stderr, flush=True)
    raise SystemExit(turn.get('exit_code', 0))


if __name__ == '__main__':
    main()
