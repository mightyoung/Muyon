from types import SimpleNamespace as NS
from pathlib import Path
from unittest.mock import patch
from tools.document_fidelity.adapters.runner.linux import kernel
class Sock:
    def fileno(self): return 101
    def close(self): pass
class Channel:
    def __init__(self,*a,**kw): pass
calls=[]
def fake_popen(*a,**kw):
    calls.append('Popen(fake)')
    return NS(pid=4242)
def no_pidfd(*a,**kw):
    calls.append('pidfd_open(fake ENOSYS)')
    raise OSError(38,'synthetic ENOSYS')
system=kernel.NativeLinuxSystem()
system.config=NS(image=Path('/pinned'))
state=NS(job=b'{}',attempt='attempt_fake',image_fd=10,source_fd=11,job_fd=12,output_fd=13,launch_fd=14,process=None,pidfd=None,uncertain=False)
with patch.object(kernel.socket,'socketpair',lambda:(Sock(),Sock())), patch.object(kernel.ipc,'Channel',Channel), patch.object(kernel.os,'fstat',lambda _:NS(st_ino=99)), patch.object(kernel.subprocess,'Popen',fake_popen), patch.object(kernel.os,'pidfd_open',no_pidfd), patch.object(kernel,'_starttime',lambda _:123):
    try: system.launch(state)
    except OSError as e: print('launch:',e)
    print('reconcile:',system.reconcile(state))
print('calls:',calls)
print('state:',dict(process_created=state.process is not None,pidfd=state.pidfd,uncertain=state.uncertain))
