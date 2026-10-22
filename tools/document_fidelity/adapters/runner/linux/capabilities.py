"""Prelaunch feature probes. Native calls NOT_RUN here; tests replace every syscall.

Only the broker itself and a disposable sealed memfd are touched by native
preflight. No process, signal delivery, namespace or bare-PID fallback is used.
"""
import fcntl,os,signal

class RuntimeCapabilityMissing(ValueError):pass

def preflight():
    required=((os,'pidfd_open'),(signal,'pidfd_send_signal'),(os,'memfd_create'),(os,'pread'),(os,'execve'),(os,'waitpid'),(fcntl,'fcntl'))
    if any(not callable(getattr(owner,name,None)) for owner,name in required):raise RuntimeCapabilityMissing('runtime_capability_api_missing')
    if os.execve not in getattr(os,'supports_fd',set()) or any(type(getattr(os,name,None)) is not int for name in ('MFD_CLOEXEC','MFD_ALLOW_SEALING')):raise RuntimeCapabilityMissing('runtime_capability_fd_exec_or_memfd_missing')
    pidfd=memfd=None
    try:
        pidfd=os.pidfd_open(os.getpid())
        signal.pidfd_send_signal(pidfd,0) # permission/feature query, no delivered signal
        memfd=os.memfd_create('document-feature-probe',os.MFD_CLOEXEC|os.MFD_ALLOW_SEALING)
        data=b'bounded-feature-probe';offset=0
        while offset<len(data):
            count=os.write(memfd,data[offset:])
            if type(count) is not int or not 0<count<=len(data)-offset:raise RuntimeCapabilityMissing('runtime_capability_memfd_write')
            offset+=count
        fcntl.fcntl(memfd,1033,15) # Linux UAPI F_ADD_SEALS; SEAL/SHRINK/GROW/WRITE
        if fcntl.fcntl(memfd,1034)&15!=15:raise RuntimeCapabilityMissing('runtime_capability_memfd_seals')
    except OSError as error:raise RuntimeCapabilityMissing('runtime_capability_kernel_denied:'+str(error.errno)) from error
    finally:
        if memfd is not None:os.close(memfd)
        if pidfd is not None:os.close(pidfd)
