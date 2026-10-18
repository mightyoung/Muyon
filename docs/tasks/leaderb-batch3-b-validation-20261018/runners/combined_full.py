import sys
sys.path.insert(0,'/workspace/leaderb-b3-b/experiments/redesign/rust-agent-host-lab/checks')
import full
from combined_guard import validate
identity=validate("/workspace/leaderb-b3-b", "/workspace/leaderb-b3-evidence/b")
from http_batch import contract
full.CASES=contract()
if __name__ == "__main__":
    status=full.main()
    import json
    from pathlib import Path
    output=Path(sys.argv[sys.argv.index("--output")+1])
    result=json.loads(output.read_text())
    result.update(combined_source=identity)
    output.write_text(json.dumps(result,indent=2)+"\n")
    raise SystemExit(status)
