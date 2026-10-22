#!/usr/bin/env python3
"""Temporary combination only; no edits to shared lib.rs or bot_drafts.rs in the checkout."""
import os,pathlib,subprocess,tempfile,shutil
root=pathlib.Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],text=True).strip())
with tempfile.TemporaryDirectory(prefix='muyon-bot-create-') as temp:
 target=pathlib.Path(temp)/'repo'
 subprocess.run(['git','clone','--quiet','--shared','--no-hardlinks',str(root),str(target)],check=True)
 for rel in ['crates/muyon-core/src/bot_definitions.rs','crates/muyon-core/src/bot_definitions/tests.rs']:
  p=root/rel
  if p.exists():
   (target/rel).parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target/rel)
 draft=subprocess.check_output(['git','show','15c65c7c9c1f0af1e73c8092b2de2ac78939eea7:crates/muyon-core/src/bot_drafts.rs'],cwd=root)
 (target/'crates/muyon-core/src/bot_drafts.rs').write_bytes(draft)
 lib=target/'crates/muyon-core/src/lib.rs'
 with lib.open('a') as f:f.write('\npub mod bot_drafts;\npub mod bot_definitions;\n')
 env=os.environ.copy();env.update(RUSTUP_HOME='/tmp/bot-rustup',CARGO_HOME='/tmp/bot-cargo',CARGO_TARGET_DIR='/tmp/bot-definitions-target',LIBRARY_PATH='/tmp/bot-sqlite-link')
 subprocess.run(['/tmp/bot-cargo/bin/cargo','test','--manifest-path',str(target/'crates/Cargo.toml'),'-p','muyon-core','--lib','bot_definitions','--','--test-threads=1','--nocapture'],env=env,check=True)
