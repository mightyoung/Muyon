"""Concrete openat/no-follow snapshot with immutable before/after metadata."""
from dataclasses import dataclass
import os,stat

@dataclass(frozen=True)
class FileInfo:
    device:int
    inode:int
    mode:int
    links:int
    size:int
    mtime_ns:int
    ctime_ns:int

class NativeFiles:
    def names(self,dirfd):return os.listdir(dirfd)
    def open_read(self,dirfd,name):return os.open(name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC,dir_fd=dirfd)
    def info(self,fd):
        value=os.fstat(fd)
        return FileInfo(value.st_dev,value.st_ino,value.st_mode,value.st_nlink,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
    def read(self,fd,count):return os.read(fd,count)
    def close(self,fd):os.close(fd)

def capture(files,dirfd,name,limit,*,reaped):
    if reaped is not True:raise ValueError('tree_must_be_reaped')
    if type(name) is not str or name in ('','.','..') or '/' in name or '\\' in name or '\x00' in name:raise ValueError('fixed_basename_required')
    if type(limit) is not int or not 0<limit<=16777216:raise ValueError('snapshot_limit')
    if files.names(dirfd)!=[name]:raise ValueError('unexpected_output_set')
    fd=files.open_read(dirfd,name)
    try:
        before=files.info(fd)
        if type(before) is not FileInfo or not stat.S_ISREG(before.mode) or before.links!=1 or not 0<before.size<=limit:raise ValueError('snapshot_file_shape')
        data=bytearray()
        while len(data)<=before.size:
            wanted=min(65536,before.size+1-len(data))
            chunk=files.read(fd,wanted)
            if type(chunk) is not bytes or len(chunk)>wanted:raise ValueError('invalid_read')
            if not chunk:break
            data.extend(chunk)
        after=files.info(fd)
        if before!=after or len(data)!=before.size or files.names(dirfd)!=[name]:raise ValueError('snapshot_changed')
        return bytes(data)
    finally:files.close(fd)
