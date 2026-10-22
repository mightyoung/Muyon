#!/usr/bin/env python3
import pathlib,subprocess,shutil,re,hashlib,struct
out=pathlib.Path(__file__).resolve().parent/'final-verification.log'
lines=[]
for name in ['cargo','rustc','rustfmt','kotlinc']:
    lines.append(f'{name}: {shutil.which(name) or "NOT_FOUND"}')
for command in [
 ['cargo','test','--manifest-path','crates/Cargo.toml','-p','muyon-core','--test','bot_drafts'],
 ['cargo','test','--manifest-path','crates/Cargo.toml','-p','muyon-android-ffi','local_draft_bridge_tests'],
 ['cargo','fmt','--manifest-path','crates/Cargo.toml','--','--check']]:
    lines.append('$ '+' '.join(command))
    try:
        result=subprocess.run(command,text=True,capture_output=True)
        lines.append(f'exit={result.returncode}\n{result.stdout}{result.stderr}')
    except FileNotFoundError:
        lines.append('NOT_RUN: cargo executable absent; no software installed')
for command in [
 ['python3','docs/tasks/local-workspace-bot-provider-20261022/evidence/sql_smoke.py'],
 ['git','apply','--check','docs/tasks/local-workspace-bot-provider-20261022/CORE-EXPORT.patch'],
 ['git','diff','--check']]:
    result=subprocess.run(command,text=True,capture_output=True)
    lines.append('$ '+' '.join(command))
    lines.append(f'exit={result.returncode}\n{result.stdout}{result.stderr}')
    out.write_text('\n'.join(lines)+'\n')
    assert result.returncode==0
src=pathlib.Path('crates/muyon-core/src/bot_drafts.rs').read_text()
assert not re.search(r'\b(?:UPDATE|INSERT INTO|DELETE FROM)\s+(?:intents|business_grants|requests)\b',src)
lines.append('PASS static no write statements target existing unknown/grant/request ledgers')
s=pathlib.Path('crates/muyon-android-ffi/src/lib.rs').read_text()
b=bytes.fromhex(re.search('let archive_hex = "([a-f0-9]+)"',s).group(1))
assert len(b)==67 and b[:8]==b'MYBD\0\0\0\1' and struct.unpack('>q',b[8:16])==(1,)
assert b[-32:]==hashlib.sha256(b[:-32]).digest()
lines.append('PASS FFI synthetic archive header/version/revision/length/checksum')
lines.append('NOT_RUN: native Rust behavior, UniFFI generation, canonical Kotlin roundtrip, late-callback host UI and Android integration')
out.write_text('\n'.join(lines)+'\n')
print(out.read_text())
