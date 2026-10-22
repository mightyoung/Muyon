from pathlib import Path
from types import SimpleNamespace as NS
from unittest.mock import patch
from tools.document_fidelity.adapters.runner.linux import kernel
native=kernel.NativeLinuxSystem()
native.config=NS(image=Path('/image'),image_manifest=(),host_libraries=(('/lib/reviewed.so','a'*64),),bwrap=Path('/bin/bwrap'),bwrap_sha256='b'*64)
line='1000-2000 r-xp 00000000 02:03 42 /lib/reviewed.so\n'
with patch.object(kernel,'_proc',return_value=line), patch.object(kernel.os,'open',return_value=99), patch.object(kernel.os,'close'), patch.object(kernel.os,'fstat',return_value=NS(st_ino=42,st_dev=kernel.os.makedev(0,1))), patch.object(kernel,'_regular_hash',return_value='a'*64):
    print('maps_device=02:03, opened_artifact_device=00:01, same_inode=42')
    print('accepted:',native._check_maps(71,False))
