"""Pinned paused sandbox supervisor source. Never launched by this test batch."""
import json,os,resource,socket,struct
from pathlib import Path
from . import ipc,seccomp
from .host_stage import read_launch
from .worker_permit import receive_permit
from ...runtime import read_regular,adapter
from ...protocol import parse_request
from .. import model

def main():
    # FD3 is fixed by host-stage; no env/JSON/CLI field installs a bootstrap.
    sock=socket.socket(fileno=3)
    peer_pid,peer_uid,_=struct.unpack('3i',sock.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))
    os.closerange(4,128)
    launch_fd=os.open('/job/launch.json',os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
    try:launch=read_launch(launch_fd)
    finally:os.close(launch_fd)
    request=parse_request(json.loads(read_regular('/job/request.json',16384)))
    spec=launch['spec'];fmt,module,engine,version,worker=adapter(request)
    if spec['format']!=fmt or launch['engine']['engine_id']!=engine or launch['engine']['version']!=version:raise ValueError('bootstrap_engine_binding')
    # Outside-PID-namespace parent credentials translate to pid0 here; only
    # inherited private FD3 with kernel credentials can authorize release.
    channel=ipc.Channel(sock,spec['attempt_id'],model.digest(request),expected_pid=peer_pid,expected_uid=peer_uid,allow_pid_zero=peer_pid==0)
    seccomp.install()
    channel.send('paused',{'stage':'waiting'},1000)
    permit=receive_permit(channel,request)
    from importlib import import_module
    worker_module=import_module('tools.document_fidelity.adapters.'+worker.removesuffix('.py'))
    worker_module.edit_copy(request,Path('/input/source.'+fmt),Path('/output/candidate.'+fmt),permit=permit)
    return 0

if __name__=='__main__':raise SystemExit(main())
