"""Linux syscall implementation. NOT executed by this batch's fake-kernel tests.

No cgroup creation/controller/limit setup, no namespace fallback. Resource domain
and dedicated subreaper broker must already be provisioned by trusted host.
"""
from dataclasses import dataclass,field,asdict
from pathlib import Path
import ctypes,fcntl,hashlib,json,os,platform,re,secrets,select,shutil,socket,stat,subprocess,time
from .. import model
from . import ipc,snapshot
from .layout import HOST_CODE,SANDBOX_CODE
from .capabilities import preflight

@dataclass(frozen=True)
class Review:
    id:str
    path:Path
    sha256:str

@dataclass(frozen=True)
class PinnedConfig:
    engine:model.EngineIdentity
    policy:model.Policy
    image:Path
    image_manifest:tuple
    engine_members:tuple
    worker_relative:str
    bwrap:Path
    bwrap_sha256:str
    workspace_parent:Path
    domain:Path
    domain_identity:tuple
    provenance:Review
    license:Review
    isolation:Review
    host_libraries:tuple=()

@dataclass
class NativeState:
    attempt:str
    spec:dict
    source:bytes
    job:bytes
    root:object=None
    root_identity:object=None
    input_fd:object=None
    job_dir_fd:object=None
    output_fd:object=None
    launch_fd:object=None
    source_fd:object=None
    job_fd:object=None
    image_fd:object=None
    root_created:bool=False
    root_creation_attempted:bool=False
    stage_complete:bool=False
    staging_failed:bool=False
    cleanup_failed:bool=False
    stage_discarded:bool=False
    quarantined:bool=False
    owned_fds:set=field(default_factory=set)
    uncertain_fds:set=field(default_factory=set)
    cleanup_errors:list=field(default_factory=list)
    process:object=None
    pidfd:object=None
    starttime:object=None
    gate:object=None
    sandbox:object=None
    child_socket_inode:object=None
    sandbox_pid:object=None
    sandbox_pidfd:object=None
    sandbox_start:object=None
    released:bool=False
    reaped:bool=False
    uncertain:bool=False
    closed:bool=False
    entry:object=None
    observations:object=None
    log_bytes:dict=field(default_factory=lambda:{'stdout':0,'stderr':0})
    log_eof:set=field(default_factory=set)


def parse_status(text):
    values={}
    for line in text.splitlines():
        if ':' in line:
            key,value=line.split(':',1)
            if key in values:raise ValueError('duplicate_status')
            values[key]=value.strip()
    required={'NoNewPrivs':10,'Seccomp':10,'Seccomp_filters':10,'CapEff':16,'CapPrm':16,'CapInh':16,'CapAmb':16}
    try:result={key:int(values[key],base) for key,base in required.items()}
    except (KeyError,ValueError) as error:raise ValueError('missing_kernel_security_field') from error
    if result['NoNewPrivs']!=1 or result['Seccomp']!=2 or result['Seccomp_filters']<1 or any(result[k] for k in ('CapEff','CapPrm','CapInh','CapAmb')):raise ValueError('kernel_security_insufficient')
    return result

def check_environment(data):
    result={}
    for raw in data.split(b'\0'):
        if not raw:continue
        name,separator,value=raw.partition(b'=')
        if not separator or name!=b'LC_CTYPE' or value not in (b'C.UTF-8',b'C.utf8') or name.decode() in result:raise ValueError('unsanitized_actual_environment')
        result[name.decode()]=value.decode()
    return result

def check_domain_values(values,policy):
    for name,cap in [('memory.max',policy.address_space_bytes),('pids.max',policy.max_pids)]:
        value=values.get(name,'max')
        if not value.isdecimal() or not 0<int(value)<=cap:raise ValueError('unbounded_resource_domain')
    if values.get('memory.swap.max')!='0' or values.get('memory.oom.group')!='1':raise ValueError('swap_or_oom_domain')
    quota,period=values.get('cpu.max','max 1').split()
    if not quota.isdecimal() or not period.isdecimal() or not 0<int(quota)<=int(period):raise ValueError('cpu_domain')
    if values.get('cgroup.type')!='domain':raise ValueError('domain_type')

def _read(fd,limit):
    data=bytearray()
    while len(data)<=limit:
        chunk=os.read(fd,min(65536,limit+1-len(data)))
        if not chunk:break
        data.extend(chunk)
    if len(data)>limit:raise ValueError('bounded_read')
    return bytes(data)

def _beneath(rootfd,relative,flags=os.O_RDONLY):
    if type(relative) is not str or relative.startswith('/') or any(p in ('','.','..') for p in relative.split('/')):raise ValueError('relative_path')
    current=os.dup(rootfd)
    try:
        parts=relative.split('/')
        for part in parts[:-1]:
            new=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=current)
            os.close(current);current=new
        return os.open(parts[-1],flags|os.O_NOFOLLOW|os.O_CLOEXEC|os.O_NONBLOCK,dir_fd=current)
    finally:os.close(current)

def _text_at(fd,name,limit=65536):
    child=_beneath(fd,name)
    try:return _read(child,limit).decode('utf-8',errors='strict').strip()
    finally:os.close(child)

def _domain_state(fd):
    """Observe an already provisioned leaf. Never configure cgroup controls.

    cgroup.events populated is recursive; cgroup.procs alone is not. A zero
    max.descendants prevents new children, but existing child groups must still
    be rejected before recursive kill, even when they are currently empty.
    """
    def leaf():
        if _text_at(fd,'cgroup.max.descendants')!='0':raise ValueError('preconfigured_leaf_domain_required')
        names=set(os.listdir(fd))
        for name in names:
            mode=os.stat(name,dir_fd=fd,follow_symlinks=False).st_mode
            if stat.S_ISDIR(mode) or stat.S_ISLNK(mode):raise ValueError('child_cgroup_forbidden')
        return names
    before=leaf()
    raw=_text_at(fd,'cgroup.procs').split()
    if any(not p.isdecimal() or int(p)<=0 for p in raw) or len(raw)!=len(set(raw)):raise ValueError('domain_members_invalid')
    members={int(p) for p in raw};events={}
    for line in _text_at(fd,'cgroup.events').splitlines():
        pair=line.split()
        if len(pair)!=2 or pair[0] in events:raise ValueError('domain_events_invalid')
        events[pair[0]]=pair[1]
    populated=events.get('populated')
    if populated not in ('0','1') or bool(members)!=(populated=='1'):raise ValueError('recursive_domain_population_mismatch')
    if before!=leaf():raise ValueError('domain_structure_changed')
    return members,populated=='1'

def _readonly_source(fd,device,mount_pid=None):
    """FD mount + underlying superblock must both be read-only.

    A readonly bind of a writable superblock is deliberately insufficient.
    Caller supplies the observed task's mount namespace for proc magic-link FDs.
    This is not a chmod test and does not accept a root-path readonly assertion.
    """
    if not os.fstatvfs(fd).f_flag&os.ST_RDONLY:raise ValueError('artifact_fd_filesystem_writable')
    info=_proc(os.getpid(),'fdinfo/'+str(fd),8192)
    ids=re.findall(r'^mnt_id:\s+(\d+)\s*$',info,re.M)
    if len(ids)!=1:raise ValueError('artifact_mount_identity_missing')
    lines=[]
    for line in _proc(os.getpid() if mount_pid is None else mount_pid,'mountinfo').splitlines():
        left,separator,right=line.partition(' - ');fields=left.split();superfields=right.split()
        if fields and fields[0]==ids[0]:lines.append((separator,fields,superfields))
    if len(lines)!=1:raise ValueError('artifact_fd_mount_not_observed')
    separator,fields,superfields=lines[0]
    expected_device=str(os.major(device))+':'+str(os.minor(device))
    if (not separator or len(fields)<6 or len(superfields)<3 or fields[2]!=expected_device
            or 'ro' not in fields[5].split(',') or 'ro' not in superfields[2].split(',')):
        raise ValueError('artifact_mount_or_superblock_not_readonly')
    return (ids[0],fields[2],superfields[0],superfields[2])

def _regular_hash(fd,limit=67108864,*,mount_pid=None):
    before=os.fstat(fd)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1 or before.st_mode&0o022:raise ValueError('untrusted_artifact_mode')
    source=_readonly_source(fd,before.st_dev,mount_pid)
    data=_read(fd,limit);after=os.fstat(fd)
    if source!=_readonly_source(fd,after.st_dev,mount_pid):raise ValueError('artifact_readonly_source_changed')
    if (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns,before.st_ctime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns,after.st_ctime_ns) or len(data)!=before.st_size:raise ValueError('artifact_changed')
    return model.sha(data)

def _proc(pid,name,limit=262144):
    fd=os.open('/proc/'+str(pid)+'/'+name,os.O_RDONLY|os.O_CLOEXEC)
    try:return _read(fd,limit).decode('utf-8',errors='strict')
    finally:os.close(fd)

def _starttime(pid):
    text=_proc(pid,'stat',8192);return int(text[text.rfind(')')+2:].split()[19])

def _limits(text,policy):
    for name,cap in [('Max cpu time',policy.cpu_seconds),('Max file size',policy.max_candidate_bytes),('Max address space',policy.address_space_bytes),('Max open files',128)]:
        match=re.search(r'^'+re.escape(name)+r'\s+(\S+)\s+(\S+)\s+\S+\s*$',text,re.M)
        if not match or any(not v.isdecimal() or int(v)>cap for v in match.groups()):raise ValueError('unbounded_process_limit')

def _mounts(text,format):
    mounts={}
    for line in text.splitlines():
        left,_,right=line.partition(' - ');parts=left.split()
        if not right or len(parts)<6:raise ValueError('mountinfo')
        target=parts[4]
        if '\\' in target or target in mounts:raise ValueError('ambiguous_mount')
        mounts[target]=set(parts[5].split(','))
        if 'rw' in mounts[target] and not any(target==p or target.startswith(p+'/') for p in ('/output','/tmp','/dev','/proc')):raise ValueError('unexpected_writable_mount')
    for target in ('/','/input/source.'+format,'/job/request.json','/job/launch.json'):
        if 'ro' not in mounts.get(target,set()):raise ValueError('readonly_mount_missing')
    if 'rw' not in mounts.get('/output',set()):raise ValueError('private_output_missing')

def _sealed(data,own=lambda fd:fd,close=os.close):
    fd=os.memfd_create('document-launch',os.MFD_CLOEXEC|os.MFD_ALLOW_SEALING)
    own(fd)
    try:
        os.write(fd,data);os.lseek(fd,0,os.SEEK_SET)
        fcntl.fcntl(fd,1033,0x0001|0x0002|0x0004|0x0008)
        return fd
    except BaseException:close(fd);raise

class RecoveredProcess:
    """Only a kernel-credential-authenticated child of this broker can recover."""
    def __init__(self,pid):self.pid=pid;self.returncode=None;self.stdout=self.stderr=None
    def poll(self):
        if self.returncode is None:
            child,status=os.waitpid(self.pid,os.WNOHANG)
            if child:self.returncode=os.waitstatus_to_exitcode(status)
        return self.returncode

class NativeLinuxSystem:
    """Actual implementation; construction performs no syscalls/configuration."""
    def __init__(self):self.config=None;self.domain_fd=None;self.image_fd=None;self.qualified=False
    def now_ms(self):return time.monotonic_ns()/1000000
    def qualify(self,config):
        if type(config) is not PinnedConfig or platform.system()!='Linux' or platform.machine()!='x86_64':raise ValueError('linux_profile_unconfigured')
        preflight()
        broker_status=_proc(os.getpid(),'status')
        if not re.search(r'^NoNewPrivs:\s+1$',broker_status,re.M) or any(int(re.search('^'+name+r':\s+([0-9a-fA-F]+)$',broker_status,re.M).group(1),16) for name in ('CapEff','CapPrm','CapAmb')):raise ValueError('preconfigured_unprivileged_nnp_broker_required')
        self.baseline_filters=int(re.search(r'^Seccomp_filters:\s+(\d+)$',broker_status,re.M).group(1)) if 'Seccomp_filters:' in broker_status else 0
        if len(os.listdir('/proc/self/task'))!=1 or _proc(os.getpid(),'task/'+str(os.getpid())+'/children').strip():raise ValueError('dedicated_broker_required')
        subreaper=ctypes.c_int()
        if ctypes.CDLL(None,use_errno=True).prctl(37,ctypes.byref(subreaper),0,0,0)!=0 or subreaper.value!=1:raise ValueError('preconfigured_subreaper_required')
        if not shutil.rmtree.avoids_symlink_attacks:raise ValueError('safe_cleanup_unavailable')
        # No creation or adjustment of host cgroup/controllers/security settings.
        domain=os.open(config.domain,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC)
        try:image=os.open(config.image,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC)
        except BaseException:os.close(domain);raise
        try:
            info=os.fstat(domain);buf=(ctypes.c_long*32)()
            if ctypes.CDLL(None,use_errno=True).fstatfs(domain,ctypes.byref(buf))!=0 or buf[0]!=0x63677270:raise ValueError('not_kernel_cgroup2')
            if (info.st_dev,info.st_ino)!=config.domain_identity or info.st_uid!=os.geteuid() or info.st_mode&0o077:raise ValueError('domain_identity_or_ownership')
            members,populated=_domain_state(domain)
            if members or populated:raise ValueError('exclusive_empty_domain_required')
            check_domain_values({name:_text_at(domain,name) for name in ('memory.max','pids.max','memory.swap.max','memory.oom.group','cpu.max','cgroup.type')},config.policy)
            image_info=os.fstat(image)
            if image_info.st_mode&0o022 or image_info.st_uid not in (0,os.geteuid()) or not os.statvfs(config.image).f_flag&os.ST_RDONLY:raise ValueError('preprovisioned_readonly_image_required')
            pins=dict(config.image_manifest)
            if len(pins)!=len(config.image_manifest) or not 1<=len(pins)<=4096 or model.digest(pins)!=config.engine.runtime_sha256:raise ValueError('runtime_manifest')
            actual=[];total=0
            for directory,dirs,files in os.walk(config.image,followlinks=False):
                for name in dirs:
                    st=os.lstat(Path(directory)/name)
                    if not stat.S_ISDIR(st.st_mode) or st.st_mode&0o022:raise ValueError('image_directory')
                for name in files:actual.append(str((Path(directory)/name).relative_to(config.image)))
            if set(actual)!=set(pins):raise ValueError('image_member_set')
            for name,expected in pins.items():
                fd=_beneath(image,name)
                try:
                    total+=os.fstat(fd).st_size
                    if total>536870912 or _regular_hash(fd)!=expected:raise ValueError('image_hash_or_limit')
                finally:os.close(fd)
            package,distribution,worker={'openpyxl':('openpyxl','openpyxl','openpyxl_worker.py'),'python-docx':('docx','python_docx','docx_worker.py'),'python-pptx':('pptx','python_pptx','pptx_worker.py')}[config.engine.engine_id]
            prefixes=('runtime/python-packages/'+package+'/', 'runtime/python-packages/'+distribution+'-'+config.engine.version+'.dist-info/')
            members={n for n in pins if n.startswith(prefixes)}
            if (not members or members!=set(config.engine_members) or len(config.engine_members)!=len(members)
                    or config.worker_relative!='runtime/python-packages/tools/document_fidelity/adapters/'+worker
                    or pins.get(config.worker_relative)!=config.engine.worker_sha256
                    or model.digest({n:pins[n] for n in members})!=config.engine.artifact_sha256):raise ValueError('engine_or_worker_manifest')
            for path,expected in [(config.bwrap,config.bwrap_sha256)]+[(r.path,r.sha256) for r in (config.provenance,config.license,config.isolation)]:
                fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
                try:
                    if _regular_hash(fd)!=expected:raise ValueError('reviewed_artifact_hash')
                finally:os.close(fd)
            parent=os.stat(config.workspace_parent,follow_symlinks=False)
            storage=os.statvfs(config.workspace_parent);fsbuf=(ctypes.c_long*32)()
            if (ctypes.CDLL(None,use_errno=True).statfs(os.fsencode(config.workspace_parent),ctypes.byref(fsbuf))!=0
                    or fsbuf[0]!=0x01021994 or storage.f_blocks*storage.f_frsize>33554432
                    or os.listdir(config.workspace_parent)):raise ValueError('predelegated_empty_bounded_tmpfs_required')
            if not stat.S_ISDIR(parent.st_mode) or parent.st_uid!=os.geteuid() or parent.st_mode&0o077:raise ValueError('private_workspace_parent')
        except BaseException:os.close(domain);os.close(image);raise
        if not Path(__file__).resolve().is_relative_to(config.image/'runtime/python-packages'):
            os.close(domain);os.close(image);raise ValueError('broker_source_must_be_pinned_readonly_image')
        self.config=config;self.domain_fd=domain;self.image_fd=image
        try:self._check_maps(os.getpid(),False)
        except BaseException:os.close(domain);os.close(image);self.config=None;raise
        self.qualified=True
        return model.digest({'image':pins,'domain':config.domain_identity,'reviews':[r.id for r in (config.provenance,config.license,config.isolation)]})
    def stage(self,attempt,spec,source,job,register):
        if not self.qualified:raise ValueError('unqualified')
        # Register the known pathname before the first mkdir/open side effect.
        # A partial stage is owned even when its cleanup also throws.
        root=self.config.workspace_parent/('document-'+secrets.token_hex(16))
        state=NativeState(attempt,spec,source,job,root)
        register(state)
        def own(fd):state.owned_fds.add(fd);return fd
        try:
            state.root_creation_attempted=True
            os.mkdir(root,0o700);state.root_created=True
            st=os.stat(root,follow_symlinks=False);state.root_identity=(st.st_dev,st.st_ino)
            for name in ('input','job','output'):(root/name).mkdir(mode=0o700)
            source_path=root/'input'/('source.'+spec['format']);job_path=root/'job'/'request.json'
            for path,data in ((source_path,source),(job_path,job)):
                fd=own(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o400))
                try:
                    offset=0
                    while offset<len(data):
                        written=os.write(fd,data[offset:])
                        if written<=0:raise OSError('staging_write_no_progress')
                        offset+=written
                finally:self._close_staged_fd(state,fd)
            launch=dict(spec=spec,host_pid=os.getpid(),host_uid=os.geteuid(),engine=asdict(self.config.engine),policy=asdict(self.config.policy),bwrap=str(self.config.bwrap),bwrap_sha256=self.config.bwrap_sha256)
            state.launch_fd=_sealed(json.dumps(launch,sort_keys=True,separators=(',',':')).encode(),own,lambda fd:self._close_staged_fd(state,fd))
            for name in ('input','job','output'):
                setattr(state,{'input':'input_fd','job':'job_dir_fd','output':'output_fd'}[name],own(os.open(root/name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC)))
            state.source_fd=own(os.open(source_path,os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC))
            state.job_fd=own(os.open(job_path,os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC))
            state.image_fd=own(os.dup(self.image_fd));state.stage_complete=True
            return state
        except BaseException:
            state.staging_failed=True
            for fd in tuple(state.owned_fds):
                try:self._close_staged_fd(state,fd)
                except BaseException:pass # retained below; never retry ambiguous close
            try:
                if state.cleanup_failed:raise ValueError('staging_fd_close_uncertain')
                if state.root_creation_attempted and not state.root_created:raise ValueError('staging_mkdir_outcome_unknown')
                if state.root_created:
                    st=os.stat(root,follow_symlinks=False)
                    if state.root_identity is None or (st.st_dev,st.st_ino)!=state.root_identity:raise ValueError('staging_root_identity_unknown')
                    shutil.rmtree(root)
                state.stage_discarded=True;state.closed=True
            except BaseException as error:
                state.cleanup_failed=True;state.cleanup_errors.append(type(error).__name__)
            raise
    def _close_staged_fd(self,state,fd):
        state.owned_fds.remove(fd)
        try:os.close(fd)
        except BaseException as error:
            # A failed close may already have released the numeric FD. Retain
            # its uncertainty, never close that integer again after reuse.
            state.uncertain_fds.add(fd);state.cleanup_failed=True
            state.cleanup_errors.append(type(error).__name__)
            raise
    def launch(self,state):
        preflight() # refresh before even socketpair/Popen; no child on missing API
        # Ownership record exists in LinuxBackend before this call. Host-stage
        # is trusted and cannot exec bwrap until explicit parent isolate gate.
        request=model.sha(state.job)
        ga,gc=socket.socketpair();sa,sc=socket.socketpair()
        state.gate=ipc.Channel(ga,state.attempt,request,expected_uid=os.geteuid())
        state.sandbox=ipc.Channel(sa,state.attempt,request,expected_uid=os.geteuid())
        state.child_socket_inode=os.fstat(sc.fileno()).st_ino
        passed=(gc.fileno(),sc.fileno(),state.image_fd,state.source_fd,state.job_fd,state.output_fd,state.launch_fd)
        argv=[str(self.config.image/'runtime/python3'),'-I','-S','-B','-c',HOST_CODE,str(self.config.image/'runtime/python-packages'),*map(str,passed)]
        try:
            state.process=subprocess.Popen(argv,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,close_fds=True,pass_fds=passed,env={},start_new_session=True)
            state.pidfd=os.pidfd_open(state.process.pid);state.starttime=_starttime(state.process.pid)
            state.gate.expected_pid=state.process.pid
            hello=state.gate.receive(1000)
            if hello.kind!='hello' or hello.pid!=state.process.pid:raise ValueError('host_stage_identity')
            self._check_maps(state.process.pid,False)
            # Attach only this already-owned paused process to an existing
            # delegated domain. No controller/limit/security configuration.
            fd=_beneath(self.domain_fd,'cgroup.procs',os.O_WRONLY)
            try:os.write(fd,str(state.process.pid).encode())
            finally:os.close(fd)
            if state.process.pid not in self._members():raise ValueError('domain_attach_not_observed')
            state.gate.send('isolate',{},1000)
            return state
        except BaseException:
            state.uncertain=state.process is None
            raise
        finally:gc.close();sc.close()
    def reconcile(self,state):
        if state.process is None:
            if state.gate is None:return False
            try:
                hello=state.gate.receive(100)
                if hello.kind!='hello' or hello.payload!={}:return False
                pid=hello.pid;start=_starttime(pid)
                parent=int(_proc(pid,'stat').split(')')[-1].split()[1])
                if parent!=os.getpid():return False
                pidfd=os.pidfd_open(pid)
                if not self._alive(pidfd) or _starttime(pid)!=start:os.close(pidfd);return False
                state.process=RecoveredProcess(pid);state.pidfd=pidfd;state.starttime=start
            except Exception:return False
        if state.pidfd is None:
            try:
                start=_starttime(state.process.pid);fd=os.pidfd_open(state.process.pid)
                if not self._alive(fd) or _starttime(state.process.pid)!=start:os.close(fd);return False
                state.pidfd=fd;state.starttime=start
            except Exception:return False
        state.uncertain=False
        return True
    def _members(self):return _domain_state(self.domain_fd)[0]
    def _domain_empty(self):
        members,populated=_domain_state(self.domain_fd)
        return not members and not populated
    def _alive(self,pidfd):return not select.select([pidfd],[],[],0)[0]
    def _verify_executable(self,pid,expected):
        fd=os.open('/proc/'+str(pid)+'/exe',os.O_RDONLY|os.O_CLOEXEC)
        try:
            actual=_regular_hash(fd,mount_pid=pid)
            if actual!=expected:raise ValueError('actual_executable_artifact_mismatch')
            return actual
        finally:os.close(fd)
    def _observe_root(self,state):
        pid=state.process.pid
        if state.pidfd is None or not self._alive(state.pidfd) or _starttime(pid)!=state.starttime:raise ValueError('root_identity_lost')
        executable=self._verify_executable(pid,self.config.bwrap_sha256)
        maps=self._check_maps(pid,False)
        if not self._alive(state.pidfd) or _starttime(pid)!=state.starttime:raise ValueError('root_changed_during_observation')
        return dict(pid=pid,start=state.starttime,executable=executable,maps=maps)
    def _observe(self,state):
        pid=state.sandbox_pid
        if not pid or not self._alive(state.sandbox_pidfd) or _starttime(pid)!=state.sandbox_start:raise ValueError('supervisor_identity_lost')
        if state.process is None or state.pidfd is None or _starttime(state.process.pid)!=state.starttime:raise ValueError('root_identity_lost')
        if pid not in self._members() or state.process.pid not in self._members():raise ValueError('not_owned_domain')
        root_observation=self._observe_root(state)
        check_environment(_proc(pid,'environ',4096).encode())
        status=parse_status(_proc(pid,'status'))
        if status['Seccomp_filters']<=self.baseline_filters:raise ValueError('child_filter_not_observed')
        self._verify_executable(pid,dict(self.config.image_manifest).get('runtime/python3'))
        cmdline=_proc(pid,'cmdline',16384).split('\x00')
        if cmdline[:6]!=['/runtime/python3','-I','-S','-B','-c',SANDBOX_CODE]:raise ValueError('actual_supervisor_entry_mismatch')
        self._check_maps(pid,True)
        _limits(_proc(pid,'limits'),self.config.policy)
        namespaces={name:os.readlink('/proc/'+str(pid)+'/ns/'+name) for name in ('user','mnt','net','pid','ipc','uts','cgroup')}
        if os.readlink('/proc/'+str(pid)+'/ns/time')!=os.readlink('/proc/self/ns/time'):raise ValueError('monotonic_time_namespace_changed')
        if any(value==os.readlink('/proc/self/ns/'+name) for name,value in namespaces.items()):raise ValueError('namespace_not_isolated')
        _mounts(_proc(pid,'mountinfo'),state.spec['format'])
        devices=_proc(pid,'net/dev');interfaces=[line.split(':',1)[0].strip() for line in devices.splitlines() if ':' in line]
        if interfaces!=['lo'] or len(_proc(pid,'net/route').strip().splitlines())!=1 or any(line.split()[-1]!='lo' or int(line.split()[0],16) not in (0,1) for line in _proc(pid,'net/ipv6_route').splitlines()):raise ValueError('network_not_empty')
        fds=os.listdir('/proc/'+str(pid)+'/fd')
        if set(fds)!={'0','1','2','3'} or os.readlink('/proc/'+str(pid)+'/fd/3')!='socket:['+str(state.child_socket_inode)+']':raise ValueError('inherited_fd_set')
        root=os.open('/proc/'+str(pid)+'/root',os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC)
        try:
            if (os.fstat(root).st_dev,os.fstat(root).st_ino)!=(os.fstat(state.image_fd).st_dev,os.fstat(state.image_fd).st_ino):raise ValueError('runtime_root_identity')
            for relative,expected in [('input/source.'+state.spec['format'],model.sha(state.source)),('job/request.json',model.sha(state.job))]:
                fd=_beneath(root,relative)
                try:
                    if model.sha(_read(fd,16777216))!=expected:raise ValueError('staged_input_mismatch')
                finally:os.close(fd)
            output=_beneath(root,'output',os.O_RDONLY|os.O_DIRECTORY)
            try:
                if (os.fstat(output).st_dev,os.fstat(output).st_ino)!=(os.fstat(state.output_fd).st_dev,os.fstat(state.output_fd).st_ino):raise ValueError('output_identity')
            finally:os.close(output)
        finally:os.close(root)
        if not self._alive(state.sandbox_pidfd) or _starttime(pid)!=state.sandbox_start:raise ValueError('identity_changed_during_observation')
        return dict(pid=pid,start=state.sandbox_start,namespaces=namespaces,status=status,domain=self.config.domain_identity,root=root_observation)
    def _check_maps(self,pid,sandbox):
        expected=dict(self.config.image_manifest);host=dict(self.config.host_libraries)
        host[str(self.config.bwrap)]=self.config.bwrap_sha256
        root=None;observed=[]
        if sandbox:root=os.open('/proc/'+str(pid)+'/root',os.O_RDONLY|os.O_DIRECTORY|os.O_CLOEXEC)
        try:
            for line in _proc(pid,'maps').splitlines():
                fields=line.split(None,5)
                if len(fields)<6 or fields[5].startswith('['):continue
                path=fields[5]
                if not path.startswith('/') or path.endswith(' (deleted)'):raise ValueError('unreviewed_mapped_object')
                if sandbox:
                    relative=path.lstrip('/');pin=expected.get(relative)
                    if pin is None:raise ValueError('unreviewed_sandbox_library')
                    fd=_beneath(root,relative)
                elif path.startswith(str(self.config.image)+'/'):
                    relative=path[len(str(self.config.image))+1:];pin=expected.get(relative)
                    if pin is None:raise ValueError('unreviewed_host_stage_object')
                    fd=_beneath(self.image_fd,relative)
                else:
                    pin=host.get(path)
                    if pin is None:raise ValueError('host_loader_library_not_reviewed')
                    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
                try:
                    info=os.fstat(fd)
                    if not re.fullmatch(r'[0-9a-fA-F]+:[0-9a-fA-F]+',fields[3]):raise ValueError('mapped_object_device')
                    device=tuple(int(p,16) for p in fields[3].split(':'))
                    if device!=(os.major(info.st_dev),os.minor(info.st_dev)) or info.st_ino!=int(fields[4]) or _regular_hash(fd,mount_pid=pid if sandbox else None)!=pin:raise ValueError('mapped_object_identity_or_hash')
                    observed.append((path,info.st_dev,info.st_ino,pin))
                finally:os.close(fd)
        finally:
            if root is not None:os.close(root)
        return observed
    def observe_ready(self,state,binding,engine,policy):
        frame=state.sandbox.receive(min(1000,policy.timeout_ms))
        if frame.kind!='paused' or frame.payload!={'stage':'waiting'}:raise ValueError('bootstrap_not_paused')
        state.sandbox_pid=frame.pid;state.sandbox_pidfd=os.pidfd_open(frame.pid);state.sandbox_start=_starttime(frame.pid)
        state.sandbox.expected_pid=frame.pid
        state.observations=self._observe(state)
        return state.observations
    def recheck_ready(self,state):return self._observe(state)==state.observations
    def release(self,state,grant):
        if state.released or not self.recheck_ready(state):raise ValueError('release_not_ready')
        state.sandbox.send('release',grant,1000);state.released=True
    def poll(self,state,wait):
        # Drain actual stdout/stderr to EOF before reporting exit; never discard
        # trailing bytes merely because root poll() is already non-None.
        streams={'stdout':state.process.stdout,'stderr':state.process.stderr}
        readers=[s for name,s in streams.items() if name not in state.log_eof]
        readable=select.select(readers+([state.sandbox.socket] if state.entry is None else []),[],[],wait/1000)[0]
        for name,stream in streams.items():
            if stream in readable:
                data=os.read(stream.fileno(),min(4096,self.config.policy.max_chunk_bytes))
                if not data:state.log_eof.add(name);continue
                state.log_bytes[name]+=len(data)
                cap=self.config.policy.max_stdout_bytes if name=='stdout' else self.config.policy.max_stderr_bytes
                if state.log_bytes[name]>cap:raise ValueError('native_log_limit')
                return model.Event(name,data=data)
        if state.sandbox.socket in readable:
            try:frame=state.sandbox.receive(max(1,min(wait,1000)))
            except ipc.ProtocolError:
                if state.entry is None:raise
                frame=None
            if frame is not None:
                if frame.kind!='entry' or frame.payload!={'engine':self.config.engine.engine_id,'version':self.config.engine.version} or state.entry is not None:raise ValueError('engine_entry_event')
                state.entry=(frame.pid,frame.seq,model.digest(frame.payload));state.sandbox.close()
        code=state.process.poll()
        if code is not None and state.log_eof=={'stdout','stderr'}:return model.Event('exit',exit_code=code)
        return model.Event('running')
    def measure(self,state):
        names=os.listdir(state.output_fd);name='candidate.'+state.spec['format']
        if not names:return model.OutputState(0,False)
        if names!=[name]:return model.OutputState(0,True)
        info=os.stat(name,dir_fd=state.output_fd,follow_symlinks=False)
        return model.OutputState(info.st_size,not stat.S_ISREG(info.st_mode) or info.st_nlink!=1)
    def terminate(self,state):
        self._signal(state,15)
    def _signal(self,state,signal):
        import signal as signals
        # Never signal a recycled numeric root PID; its original pidfd is the
        # authority. Newly discovered descendants are pinned and rechecked in
        # this exact exclusive resource domain before a signal is delivered.
        if state.pidfd is not None:
            try:signals.pidfd_send_signal(state.pidfd,signal)
            except ProcessLookupError:pass
        for pid in self._members():
            if state.process is not None and pid==state.process.pid:continue
            try:
                before=_starttime(pid);fd=os.pidfd_open(pid)
                try:
                    if not self._alive(fd):continue
                    if _starttime(pid)!=before or pid not in self._members():raise ValueError('descendant_identity_changed')
                    signals.pidfd_send_signal(fd,signal)
                finally:os.close(fd)
            except ProcessLookupError:pass
    def kill(self,state):
        # Domain identity and exclusive ownership were pinned before launch.
        _domain_state(self.domain_fd) # recursive kill must not touch a child group
        fd=_beneath(self.domain_fd,'cgroup.kill',os.O_WRONLY)
        try:os.write(fd,b'1')
        finally:os.close(fd)
        if state.process is not None and state.process.poll() is None:self._signal(state,9)
    def reap(self,state,wait):
        if state.uncertain or state.process is None:return False
        deadline=self.now_ms()+wait
        while True:
            code=state.process.poll()
            if code is not None:
                # Qualified dedicated broker is already a subreaper. Reap only
                # its owned adopted descendants; it had no other children.
                children=_proc(os.getpid(),'task/'+str(os.getpid())+'/children').split()
                for child in children:
                    if int(child)!=state.process.pid:
                        try:os.waitpid(int(child),os.WNOHANG)
                        except ChildProcessError:pass
                if self._domain_empty() and not _proc(os.getpid(),'task/'+str(os.getpid())+'/children').strip():state.reaped=True;return True
            if self.now_ms()>=deadline:return False
            time.sleep(min(0.005,max(0,(deadline-self.now_ms())/1000)))
    def capture(self,state,policy):
        if not state.reaped or not self._domain_empty():raise ValueError('tree_not_reaped')
        files=snapshot.NativeFiles()
        candidate=snapshot.capture(files,state.output_fd,'candidate.'+state.spec['format'],policy.max_candidate_bytes,reaped=True)
        source=snapshot.capture(files,state.input_fd,'source.'+state.spec['format'],policy.max_input_bytes,reaped=True)
        job=snapshot.capture(files,state.job_dir_fd,'request.json',16384,reaped=True)
        return model.Snapshot(candidate,source,job,True,1,False)
    def cleanup(self,state):
        if not state.reaped or not self._domain_empty():raise ValueError('live_job_cleanup_forbidden')
        st=os.stat(state.root,follow_symlinks=False)
        if (st.st_dev,st.st_ino)!=state.root_identity:raise ValueError('workspace_identity_changed')
        self._close(state);shutil.rmtree(state.root)
    def _close(self,state):
        if state.closed:return
        for channel in (state.gate,state.sandbox):
            if channel is not None:channel.close()
        for fd in tuple(state.owned_fds):self._close_staged_fd(state,fd)
        for fd in (state.pidfd,state.sandbox_pidfd):
            if fd is not None:os.close(fd)
        if state.process is not None:
            for stream in (state.process.stdout,state.process.stderr):
                if stream is not None:stream.close()
        state.closed=True
    def quarantine(self,state):
        # Keep owned handles/workspace for reconciliation; never delete unknown
        # live state or silently retry a refused/uncertain launch.
        state.quarantined=True
        if state.gate is not None:state.gate.close()
        if state.sandbox is not None:state.sandbox.close()
