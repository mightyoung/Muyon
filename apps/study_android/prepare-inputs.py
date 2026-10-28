#!/usr/bin/env python3
"""Fetch the fixed Apache-2.0 Chinese model; verify before bundling."""
import hashlib,pathlib,urllib.request,os,json,shutil
root=pathlib.Path(__file__).resolve().parent
target=root/'app/src/main/assets/model.zip'
digest='3af8b0e7e0f835ae9d414ce5df580237a3cfb08d586c9fbbb0f7ff29ad5b14ba'
target.parent.mkdir(parents=True,exist_ok=True)
if not target.exists():
    staging=target.with_suffix('.download')
    urllib.request.urlretrieve('https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip',staging)
    assert hashlib.sha256(staging.read_bytes()).hexdigest()==digest,'Model checksum mismatch'
    staging.replace(target)
assert hashlib.sha256(target.read_bytes()).hexdigest()==digest,'Model checksum mismatch'
print('Verified bundled Chinese model: vosk-model-small-cn-0.22 (Apache-2.0)')

# Optional user-owned fixture; never fetched or published by this project.
private_papers=os.environ.get("MUYON_MEM_PAPERS")
if private_papers:
    source=pathlib.Path(private_papers).expanduser().resolve()
    data=json.loads(source.read_text(encoding="utf-8-sig"))
    assert isinstance(data,list),"Question package must be a MEM papers.json array"
    shutil.copyfile(source,root/"app/src/main/assets/mem-papers.json")
    print("Copied personal question package locally (git ignored)")
