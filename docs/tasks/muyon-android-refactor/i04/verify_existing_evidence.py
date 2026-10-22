"""Read-only audit of sealed I04 records. Does not execute recovery behavior."""

import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / "docs/tasks/leaderb-next-20261018"


def main():
    index = json.loads((BASE / "EVIDENCE-INDEX.json").read_text())
    seal = json.loads((BASE / "SEAL.json").read_text())
    for relative in ["HANDOFF.md", "evidence/I04-BLOCKED.json"]:
        entry = next(item for item in index["files"] if item["path"] == relative)
        data = (BASE / relative).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        assert len(data) == entry["bytes"], relative
        assert digest == entry["sha256"], relative
        print(f"PASS sealed artifact: {relative} sha256={digest}")
    digest = hashlib.sha256((BASE / "EVIDENCE-INDEX.json").read_bytes()).hexdigest()
    assert digest == seal["index_sha256"], "index seal"
    assert seal["i04"] == "DENIED_BEFORE_EXECUTION/BLOCKED"
    print("PASS index seal; I04=" + seal["i04"])
    denial = json.loads((BASE / "evidence/I04-BLOCKED.json").read_text())
    assert denial["outcome"] == "DENIED_BEFORE_EXECUTION"
    print("HISTORICAL DENIAL:", denial["reason"])
    print("HISTORICAL TARGET:", denial["target"])
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    print("AUDIT BASE:", head)
    candidate = subprocess.check_output(
        ["git", "cat-file", "-t", "3f1be180bb009a91e659c113ba5b1916e5360332"],
        cwd=ROOT, text=True,
    ).strip()
    assert candidate == "commit"
    print("REFERENCED CANDIDATE OBJECT:", candidate)
    requested = ROOT / "docs/tasks/LEADERB-HANDOFF-20261018-BATCH4.md"
    print("REQUESTED HANDOFF EXISTS:", requested.exists())
    print("RC01 behavioral execution: NOT_RUN; evidence audit only")


if __name__ == "__main__":
    main()
