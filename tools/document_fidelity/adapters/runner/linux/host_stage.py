"""Trusted gated host-stage source. CLI/native path is NOT_RUN in this environment."""
import fcntl,json,os,resource,socket,struct,sys
from . import ipc
from .layout import SANDBOX_CODE
from .kernel import _regular_hash

F_ADD_SEALS=1033
F_GET_SEALS=1034
SEALS=0x0001|0x0002|0x0004|0x0008 # Linux UAPI linux/fcntl.h; source-only here

def read_launch(fd):
    if fcntl.fcntl(fd,F_GET_SEALS)&SEALS!=SEALS:raise ValueError('sealed_launch_required')
    data=os.pread(fd,32769,0)
    if len(data)>32768:raise ValueError('launch_limit')
    value=json.loads(data)
    if type(value) is not dict or set(value)!={'spec','host_pid','host_uid','engine','policy','bwrap','bwrap_sha256'}:raise ValueError('launch_shape')
    return value

def bwrap_argv(launch):
    spec=launch['spec'];fmt=spec['format']
    if fmt not in ('xlsx','docx','pptx'):raise ValueError('format')
    return [launch['bwrap'],'--unshare-all','--die-with-parent','--new-session','--uid','0','--gid','0','--cap-drop','ALL','--clearenv',
            '--ro-bind','/proc/self/fd/4','/','--dir','/input','--ro-bind','/proc/self/fd/5','/input/source.'+fmt,
            '--dir','/job','--ro-bind','/proc/self/fd/6','/job/request.json','--ro-bind','/proc/self/fd/8','/job/launch.json',
            '--dir','/output','--bind','/proc/self/fd/7','/output','--proc','/proc','--dev','/dev','--tmpfs','/tmp',
            '--chdir','/output','--preserve-fds','6','/runtime/python3','-I','-S','-B','-c',SANDBOX_CODE]

def main(args=None):
    args=sys.argv[1:] if args is None else args
    if len(args)!=7:raise ValueError('fixed_inherited_fds_required')
    gate_fd,sandbox_fd,image_fd,source_fd,job_fd,output_fd,launch_fd=map(int,args)
    if len(set(map(int,args)))!=7 or min(map(int,args))<3:raise ValueError('fd_alias')
    launch=read_launch(launch_fd);spec=launch['spec'];job=os.pread(job_fd,16385,0)
    if len(job)>16384:raise ValueError('job_limit')
    import hashlib
    sock=socket.socket(fileno=gate_fd)
    pid,uid,gid=struct.unpack('3i',sock.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))
    if pid!=os.getppid() or pid!=launch['host_pid'] or uid!=launch['host_uid']:raise ValueError('host_gate_peer')
    channel=ipc.Channel(sock,spec['attempt_id'],hashlib.sha256(job).hexdigest(),expected_pid=pid,expected_uid=uid)
    channel.send('hello',{},1000)
    frame=channel.receive(1000)
    if frame.kind!='isolate' or frame.payload!={}:raise ValueError('host_gate_not_released')
    policy=launch['policy']
    for kind,cap in [(resource.RLIMIT_CPU,policy['cpu_seconds']),(resource.RLIMIT_AS,policy['address_space_bytes']),(resource.RLIMIT_FSIZE,policy['max_candidate_bytes']),(resource.RLIMIT_NOFILE,128),(resource.RLIMIT_CORE,0)]:resource.setrlimit(kind,(cap,cap))
    executable=os.open(launch['bwrap'],os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
    if _regular_hash(executable)!=launch['bwrap_sha256']:raise ValueError('bwrap_changed')
    # Duplicate above target range first to avoid FD remapping aliases. Only
    # broker socket3 and fixed read-only/image/private-output descriptors remain.
    originals=(sandbox_fd,image_fd,source_fd,job_fd,output_fd,launch_fd,executable)
    copies=[fcntl.fcntl(fd,fcntl.F_DUPFD_CLOEXEC,32) for fd in originals]
    for target,fd in enumerate(copies,3):os.dup2(fd,target,inheritable=target<9)
    for name in os.listdir('/proc/self/fd'):
        if int(name)>=10:
            try:os.close(int(name))
            except OSError as error:
                if error.errno!=9:raise
    if os.execve not in os.supports_fd:raise ValueError('pinned_fd_exec_unavailable')
    os.execve(9,bwrap_argv(launch),{})

if __name__=='__main__':main()
