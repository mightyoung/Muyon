"""Build the private Kaggle notebook. It does not read credentials or push weights."""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
NOTEBOOK = HERE / "laya_finetune_tool_selection_kaggle.ipynb"
TRAIN = HERE / "train_ddp.py"
MODEL_ID = "convaiinnovations/laya-multilingual"
REVISION = "1720e3e3357cfe1e281542e223f8273b0890ca34"
OUTPUT_DIR = "/kaggle/working/laya-muyon-tool-selection"


def _code(source: str) -> dict:
    return {
        "cell_type": "code",
        "metadata": {},
        "execution_count": None,
        "outputs": [],
        "source": source,
    }


def _markdown(source: str) -> dict:
    return {"cell_type": "markdown", "metadata": {}, "source": source}


def notebook() -> dict:
    train = TRAIN.read_text(encoding="utf-8")
    if "'''" in train or '"""' in train:
        raise RuntimeError("train_ddp.py cannot be embedded in a triple-quoted cell")
    write_train = (
        "from pathlib import Path\n"
        'Path("/kaggle/working/train_ddp.py").write_text(r"""'
        + train
        + '""")\n'
        'print("wrote", Path("/kaggle/working/train_ddp.py").stat().st_size, "bytes")\n'
    )
    preprocess = f'''import json
import os
from collections import Counter
from pathlib import Path

import torch
from huggingface_hub import snapshot_download
from laya.agent import _fix_tokenizer_config
from laya.common import QTYPES, build_sequence, render_options
from transformers import AutoTokenizer

MODEL_ID = "{MODEL_ID}"
REVISION = "{REVISION}"
MAX_LEN = 1024
HEAD_MAX_LEN = 512

matches = sorted(Path("/kaggle/input").rglob("train_set.jsonl"))
if len(matches) != 1:
    raise SystemExit(f"expected one train_set.jsonl under /kaggle/input, found {{matches}}")
rows = [json.loads(line) for line in matches[0].read_text(encoding="utf-8").splitlines() if line.strip()]
print(f"loaded {{len(rows)}} rows from {{matches[0]}}")
print("by category", dict(Counter(row["category"] for row in rows)))

print(f"Fetching {{MODEL_ID}} @ {{REVISION}}")
model_dir = snapshot_download(MODEL_ID, revision=REVISION)
_fix_tokenizer_config(model_dir)
tok = AutoTokenizer.from_pretrained(os.path.join(model_dir, "tokenizer"))
with open(os.path.join(model_dir, "rl_agent_config.json"), encoding="utf-8") as handle:
    cfg = json.load(handle)
cfg["max_len"] = MAX_LEN
cfg["head_max_len"] = HEAD_MAX_LEN


def build_training_item(state, question, gold):
    kind = question["type"]
    criteria = question.get("criteria", {{}})
    if kind == "choice":
        keys = list(criteria.keys())
        target = [gold["probabilities"].get(key, 0.0) for key in keys]
    elif kind == "noul":
        target = [gold["probabilities"].get("false", 0.5), gold["probabilities"].get("true", 0.5)]
    elif kind == "score":
        levels = len(criteria) if isinstance(criteria, list) else 4
        target = [gold["probabilities"].get(str(index), 0.0) for index in range(levels)]
    else:
        raise ValueError(kind)
    total = sum(target)
    target = [value / total for value in target] if total > 0 else [1.0 / len(target)] * len(target)
    label = target.index(max(target))
    rendered = len(render_options({{"t": kind, "crit": criteria}}))
    sequence, markers = build_sequence(
        tok,
        state,
        {{"t": kind, "ins": question["instructions"], "crit": criteria}},
        cfg["max_len"],
        cfg["head_max_len"],
    )
    if len(markers) != rendered:
        return None
    return {{
        "ids": sequence,
        "markers": markers,
        "qtype": QTYPES[kind],
        "target": target,
        "label": label,
    }}


items = []
dropped = 0
for row in rows:
    for qid, question in row["questions"].items():
        if qid not in row["gold"]:
            continue
        item = build_training_item(row["state"], question, row["gold"][qid])
        if item is None:
            dropped += 1
        else:
            items.append(item)
print(f"kept {{len(items)}} dropped {{dropped}}")
if len(items) < 1000 or dropped > len(items) // 20:
    raise SystemExit("preprocessing dropped too many rows")
torch.save(items, "/kaggle/working/train_items.pt")
Path("/kaggle/working/preprocess_manifest.json").write_text(
    json.dumps(
        {{
            "model": MODEL_ID,
            "revision": REVISION,
            "rows": len(rows),
            "items": len(items),
            "dropped": dropped,
            "maxLen": MAX_LEN,
            "headMaxLen": HEAD_MAX_LEN,
            "byCategory": dict(Counter(row["category"] for row in rows)),
        }},
        indent=2,
    )
    + "\\n",
    encoding="utf-8",
)
'''
    launch = f'''import torch

n_gpu = torch.cuda.device_count()
print("cuda", torch.cuda.is_available(), "gpus", n_gpu)
for index in range(n_gpu):
    props = torch.cuda.get_device_properties(index)
    print(f"GPU {{index}}: {{props.name}} {{props.total_memory / 1e9:.1f}} GB")
if n_gpu < 2:
    raise SystemExit("need GPU T4 x2 (machine_shape NvidiaTeslaT4)")

OUTPUT_DIR = "{OUTPUT_DIR}"
cmd = f"torchrun --standalone --nproc_per_node=2 /kaggle/working/train_ddp.py {{model_dir}} {{OUTPUT_DIR}}"
print(cmd)
!{{cmd}}
'''
    cells = [
        _markdown(
            "# Muyon tool-selection fine-tune\n\n"
            "Private synthetic choices only. The base checkpoint is "
            f"`{MODEL_ID}` at `{REVISION}`. "
            "This notebook does not upload weights anywhere."
        ),
        _markdown("## Install the same Laya release measured locally"),
        _code(
            '!pip install -q "laya==0.3.27" "transformers>=4.48.0" '
            '"safetensors>=0.4.0" "huggingface_hub>=0.20.0"\n'
            "import laya\n"
            "import torch\n"
            'print("laya", laya.__version__)\n'
            'print("torch", torch.__version__)\n'
        ),
        _markdown("## Tokenize the mounted private JSONL"),
        _code(preprocess),
        _markdown("## Write the training script and run it on both GPUs"),
        _code(write_train),
        _code(launch),
        _markdown("## Leave the weights in the kernel output"),
        _code(
            "from pathlib import Path\n"
            'Path("/kaggle/working/NO_HUB_PUSH").write_text(\n'
            '    "Hub push disabled. Weights stay in the kernel output.\\n",\n'
            '    encoding="utf-8",\n'
            ")\n"
            'print("NO_HUB_PUSH")\n'
        ),
    ]
    return {
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "pygments_lexer": "ipython3"},
        },
        "cells": cells,
    }


def main() -> None:
    document = notebook()
    NOTEBOOK.write_text(json.dumps(document, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {NOTEBOOK.name} cells={len(document['cells'])}")


if __name__ == "__main__":
    main()
