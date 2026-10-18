"""Independent process kernel-flock observation; never a process-local controller slot."""
import errno
import fcntl
import sys
with open(sys.argv[1], 'r+b') as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        if error.errno not in {errno.EAGAIN, errno.EWOULDBLOCK, errno.EACCES}:
            raise
        print('busy')
    else:
        print('available')
