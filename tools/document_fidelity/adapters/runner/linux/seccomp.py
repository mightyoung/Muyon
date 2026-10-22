"""Pinned x86_64 child-only seccomp gate source. Never installed in these tests.

Constants from local Linux headers; native install/compatibility remains NOT_RUN.
No host/global security configuration is changed by importing this module.
"""
import ctypes,errno,platform
# After bootstrap/import setup: prohibit process launch, namespace changes,
# network creation, kernel escape helpers and cross-process memory/debug access.
DENIED=(41,42,43,49,50,53,56,57,58,59,101,155,165,166,272,288,304,308,310,311,321,322,425,435,442)

def program():
    # BPF load arch; kill wrong arch; load nr; reject x32; deny listed calls.
    ops=[(0x20,0,0,4),(0x15,1,0,0xc000003e),(0x06,0,0,0x80000000),(0x20,0,0,0),
         (0x45,0,1,0x40000000),(0x06,0,0,0x80000000)]
    for number in DENIED:ops.extend([(0x15,0,1,number),(0x06,0,0,0x00050000|errno.EPERM)])
    ops.append((0x06,0,0,0x7fff0000));return tuple(ops)

def install():
    if platform.system()!='Linux' or platform.machine()!='x86_64':raise RuntimeError('seccomp_profile_unsupported')
    class Filter(ctypes.Structure):_fields_=[('code',ctypes.c_ushort),('jt',ctypes.c_ubyte),('jf',ctypes.c_ubyte),('k',ctypes.c_uint)]
    class Program(ctypes.Structure):_fields_=[('len',ctypes.c_ushort),('filter',ctypes.POINTER(Filter))]
    instructions=program();filters=(Filter*len(instructions))(*(Filter(*op) for op in instructions));descriptor=Program(len(instructions),filters)
    libc=ctypes.CDLL(None,use_errno=True)
    if libc.prctl(38,1,0,0,0)!=0 or libc.prctl(22,2,ctypes.byref(descriptor),0,0)!=0:raise OSError(ctypes.get_errno(),'child_seccomp_not_installed')
