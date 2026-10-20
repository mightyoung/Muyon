"""Explicit operator-only local FIFO handover. Never sends a chat request.

No shell evaluation of .env, endpoint/model configuration, key arguments, key
logs, temporary key files or retries. Python parsing may create immutable memory
copies: they live only in this short-lived, core-dump-disabled process.
"""
import argparse
import os
from pathlib import Path
import re
import resource
import shlex
import stat
import subprocess
import sys

SERIAL = 'emulator-5554'
PACKAGE = 'com.mightyoung.muyon.androidlab.liveChat'
DIRECTORY = 'no_backup/ordinary-chat-credential'
FIFO = DIRECTORY + '/credential.fifo'
ADB = Path.home() / 'Library/Android/sdk/platform-tools/adb'
MAX_SOURCE = 65536
IDENTITY = re.compile(rb'[0-9]{1,20}:[0-9]{1,20}:[0-9]{1,10}:600')
SINGLE_TOKEN = re.compile(rb'(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{16,128}(?![A-Za-z0-9_-])')


class Refused(Exception):
    def __init__(self):
        super().__init__('local_credential_handoff_refused')


def require(value):
    if not value:
        raise Refused()


def parse_key(source, single_key_token=False):
    try:
        return _parse_key(source, single_key_token)
    except Exception:
        raise Refused() from None


def _parse_key(source, single_key_token=False):
    require(0 < len(source) <= MAX_SOURCE and b'\0' not in source)
    if single_key_token:
        # Labels may be UTF-8. Only the single complete token is accepted as ASCII.
        bytes(source).decode('utf-8', errors='strict')
        matches = list(SINGLE_TOKEN.finditer(source))
        require(len(matches) == 1)
        key = bytearray(matches[0].group())
    else:
        text = bytes(source).decode('ascii', errors='strict')
        found = None
        for line in text.splitlines():
            stripped = line.strip(' \t')
            if not stripped or stripped.startswith('#'):
                continue
            match = re.fullmatch(r'(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*(.*)', stripped)
            require(match is not None)
            name, value = match.groups()
            literal = re.fullmatch(r"'([^'\\$`\r\n]*)'(?:[ \t]+#[^\r\n]*)?|\"([^\"\\$`\r\n]*)\"(?:[ \t]+#[^\r\n]*)?|([^\s#'\"\\$`]+)(?:[ \t]+#[^\r\n]*)?", value)
            require(literal is not None)
            if name == 'DEEPSEEK_API_KEY':
                require(found is None)
                found = next(group for group in literal.groups() if group is not None)
        require(found is not None)
        key = bytearray(found, 'ascii')
    try:
        require(16 <= len(key) <= 512 and all(33 <= value <= 126 for value in key))
        return key
    except Exception:
        key[:] = b'\0' * len(key)
        raise Refused() from None


def adb_command(remote):
    # adb's remote shell must pass the whole fixed script as ONE sh -c argument.
    return [str(ADB), '-s', SERIAL, 'exec-in', 'run-as', PACKAGE, 'sh', '-c', shlex.quote(remote)]


def identity_command():
    # Readiness metadata only. The write below rechecks the actual opened fd.
    return (f'test -d {DIRECTORY} && test ! -L {DIRECTORY} && '
            f'test "$(stat -c %a {DIRECTORY})" = 700 && '
            f'test "$(stat -c %u {DIRECTORY})" = "$(id -u)" && '
            f'test -p {FIFO} && test ! -L {FIFO} && '
            f'test "$(stat -c %a {FIFO})" = 600 && '
            f'test "$(stat -c %u {FIFO})" = "$(id -u)" && stat -c %d:%i:%u:%a {FIFO}')


def write_command(identity):
    require(IDENTITY.fullmatch(identity) is not None)
    expected = identity.decode('ascii')
    # Never cat to the pathname. A missing/replaced path can create an EMPTY file,
    # but no key bytes flow until this exact opened fd is a FIFO with the pinned identity.
    inner = (f'exec 3> {FIFO}; test -p /proc/self/fd/3 || exit 71; '
             f'test "$(stat -Lc %d:%i:%u:%a /proc/self/fd/3)" = {expected} || exit 72; cat >&3')
    return 'toybox timeout 5 sh -c ' + shlex.quote(inner)


def invoke(command, frame=None):
    child = None
    try:
        child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = child.communicate(input=frame, timeout=8)
        require(child.returncode == 0 and not stderr)
        return stdout
    except (Exception, KeyboardInterrupt):
        if child is not None and child.poll() is None:
            child.kill()
            child.communicate()
        raise Refused() from None


def read_source(path):
    source = bytearray()
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC)
        metadata = os.fstat(descriptor)
        require(stat.S_ISREG(metadata.st_mode) and 0 < metadata.st_size <= MAX_SOURCE)
        while len(source) <= MAX_SOURCE:
            chunk = os.read(descriptor, MAX_SOURCE + 1 - len(source))
            if not chunk:
                break
            source.extend(chunk)
        require(len(source) == metadata.st_size and len(source) <= MAX_SOURCE)
        return source
    except (Exception, KeyboardInterrupt):
        source[:] = b'\0' * len(source)
        raise Refused() from None
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except Exception:
                source[:] = b'\0' * len(source)
                raise Refused() from None


class FixedParser(argparse.ArgumentParser):
    def error(self, message):
        raise Refused()


def main(argv=None):
    source = bytearray(); key = bytearray(); frame = bytearray()
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        parser = FixedParser(description=__doc__)
        parser.add_argument('--env', type=Path)
        parser.add_argument('--single-key-token', action='store_true')
        parser.add_argument('--dry-run', action='store_true')
        args = parser.parse_args(argv)
        if args.dry_run:
            require(args.env is None)
            source.extend(b'DEEPSEEK_API_KEY=sk-offline-dummy-credential-00000000\n')
            key = parse_key(source)
            require('cat >&3' in write_command(b'1:2:10000:600'))
            print('DRY_RUN_NO_SECRET_NO_DEVICE')
            return 0
        require(args.env is not None)
        identity = invoke(adb_command(identity_command())).strip()
        require(IDENTITY.fullmatch(identity) is not None)
        source = read_source(args.env)
        key = parse_key(source, args.single_key_token)
        frame.extend(key); frame.append(10)
        require(not invoke(adb_command(write_command(identity)), frame))
        print('PIPE_SENT; INSTALL_NOT_VERIFIED')
        return 0
    except (Exception, KeyboardInterrupt):
        print('LOCAL_CREDENTIAL_HANDOFF_REFUSED', file=sys.stderr)
        return 1
    finally:
        for value in (frame, key, source):
            value[:] = b'\0' * len(value)


if __name__ == '__main__':
    raise SystemExit(main())
