#!/usr/bin/python3
"""Artificial child exclusively for host negative codec/correlation tests."""
import json
import struct
import sys


def exact(size):
    data = b''
    while len(data) < size:
        chunk = sys.stdin.buffer.read(size - len(data))
        if not chunk:
            raise SystemExit(0)
        data += chunk
    return data


def read():
    size = struct.unpack('>I', exact(4))[0]
    return json.loads(exact(size))


def raw(payload):
    sys.stdout.buffer.write(struct.pack('>I', len(payload)) + payload)
    sys.stdout.buffer.flush()


def send(message):
    raw(json.dumps(message, separators=(',', ':')).encode())


def main():
    mode = sys.argv[1]
    start = read()
    request = {
        'v': 1, 'kind': 'model_request', 'request_id': 1,
        'task_id': start['task_id'], 'attempt_id': start['attempt_id'],
        'turn': 1, 'messages': [{'role': 'user', 'content': start['prompt']}],
        'tools': [start['tool']],
    }
    if mode == 'wrong_task':
        request['task_id'] = 'unrelated-task'
    elif mode == 'wrong_attempt':
        request['attempt_id'] = 'unrelated-attempt'
    elif mode == 'wrong_turn':
        request['turn'] = 2
    elif mode == 'unknown_key':
        request['approval'] = True
    elif mode == 'double_request_id':
        request['request_id'] = 1.0
    elif mode == 'boolean_request_id':
        request['request_id'] = True
    elif mode == 'duplicate_key':
        payload = json.dumps(request, separators=(',', ':')).encode()
        raw(payload[:-1] + b',"request_id":2}')
        read()
        return
    elif mode == 'bad_utf8':
        raw(b'\xff')
        read()
        return
    elif mode == 'zero_length':
        sys.stdout.buffer.write(b'\x00\x00\x00\x00')
        sys.stdout.buffer.flush()
        read()
        return
    elif mode == 'oversized_length':
        sys.stdout.buffer.write(struct.pack('>I', 65537))
        sys.stdout.buffer.flush()
        read()
        return
    elif mode == 'truncated_frame':
        sys.stdout.buffer.write(struct.pack('>I', 100) + b'{}')
        sys.stdout.buffer.flush()
        return
    elif mode == 'raw_stderr':
        sys.stderr.write('UNTRUSTED_CHILD_ERROR_CANARY_92d1')
        return
    elif mode == 'forged_receipt_terminal':
        send({
            'v': 1, 'kind': 'terminal', 'task_id': start['task_id'],
            'attempt_id': start['attempt_id'], 'status': 'completed',
            'reason': 'completed', 'answer': 'fabricated result',
            'receipt_ref': 'invented-receipt',
            'projection': {'found': True, 'objectRefs': [{
                'moduleId': 'inquiry', 'objectType': 'supplier',
                'objectId': 'invented-object', 'revisionRef': None,
                'contentDigest': None,
            }]}, 'model_turns': 0, 'tool_invocations': 1,
        })
        read()
        return
    send(request)
    read()
    if mode == 'duplicate_callback':
        send(request)
        read()


if __name__ == '__main__':
    main()
