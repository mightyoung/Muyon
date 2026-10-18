"""Fresh seventeenth inverse only, with the unchanged original compiled ACK/physical oracle. Does not run the historical broad Rust classifier."""
import argparse,json,re,sys,shutil,subprocess,tempfile
from pathlib import Path
from combined_guard import validate
root=Path('/workspace/leaderb-b3-b');evidence=Path('/workspace/leaderb-b3-evidence/b');validate(root,evidence)
source=root/'experiments/redesign/core-agent-lab/core'
args=argparse.Namespace(evidence_dir=evidence/'legacy17-combined');args.evidence_dir.mkdir(parents=True)
results=[]
original=(source/'mutations.py').read_text();physical=original[original.index('# A separate inverse proves'):]
exec(compile(physical,str(source/'mutations.py')+':physical-only','exec'))
