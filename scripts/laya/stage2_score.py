#!/usr/bin/env python3
"""Gate 2: score the Kaggle fine-tune on this Mac, CPU, offline.

Fits the decision threshold on the local validation fold (rows withheld from
Kaggle), re-weighted to the 67 answerable held-out tasks. The 140-task file
and the negation set are scored after that fit and never fit on. Asks the same
way as baseline67.py (one system_one call per request, 4 threads) so latency
is comparable. Run baseline67.py first; its numbers are the D-R6 reference.

Writes ~/.cache/muyon-eval/stage2-metrics.json. Exit 2 when the gate fails,
3 when another heavy job is on the machine.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import stage1_ask as stage1  # noqa: E402  (sets the offline, 4-thread env)
import stage1_contract as contract  # noqa: E402
import stage2_threshold as gate  # noqa: E402

CACHE = Path.home() / ".cache/muyon-eval"
# Fine-tunes by version: (directory, SHA-256 recorded at download).
MODELS = {
    "v1": (
        CACHE / "models/laya-muyon-tool-selection/laya-muyon-tool-selection",
        "ef9dbf9aee506e00eb061a0989a468578eebe5b74352696cafc5c66fe994005f",
    ),
    # v2: same 4 epochs, plus 300 negate-only rows (label none).
    "v2": (
        CACHE / "models/laya-muyon-tool-selection-v2/laya-muyon-tool-selection",
        "719e30265c3dcb28799178e1fed8015ac521a1033671ec8c80ea40925337f9b9",
    ),
}
VERSION = sys.argv[1] if len(sys.argv) > 1 else "v1"
MODEL, WEIGHTS_SHA256 = MODELS[VERSION]
OUT = CACHE / f"stage2-metrics-{VERSION}.json"
BASELINE67 = CACHE / "baseline67-metrics.json"
STAGE1B = CACHE / "stage1b-metrics.json"
WEAK = ("chinese", "mixed", "paraphrase")
LATENCY_RATIO = 1.5
# A forbidden read action must not run. Gate 2 first only required no false
# write on the negation set; v1 passed that at 8/24 by picking the very read
# tool the user forbade, so accuracy is now part of the gate.
NEGATION_MIN_SHARE = 0.9


def sha256(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def scored(rows: list[dict], threshold: float) -> dict:
    return contract.summarize(rows, [contract.judge_row(row, threshold) for row in rows])


def weak_counts(summary: dict) -> dict[str, int]:
    return {c: summary["byCategory"].get(c, {}).get("top1", 0) for c in WEAK}


def stage1b_on(ids: set[str]) -> dict:
    """Stage 1b's kept decision (choice-only, threshold 1.0) on the same tasks."""
    payload = json.loads(STAGE1B.read_text(encoding="utf-8"))
    threshold = payload["decision"]["threshold"]
    rows = [
        {**row, "dangerous": []}
        for row in payload["predictions"]
        if row["split"] == "eval" and row["id"] in ids
    ]
    if len(rows) != len(ids):
        raise SystemExit(f"stage 1b has {len(rows)} of {len(ids)} answerable rows")
    return scored(rows, threshold)


def main() -> int:
    busy = stage1.other_heavy_jobs()
    if busy:
        print("machine busy; not measuring", *busy, sep="\n", flush=True)
        return 3
    if not BASELINE67.exists():
        print("run baseline67.py first", flush=True)
        return 3
    if sha256(MODEL / "model.safetensors") != WEIGHTS_SHA256:
        raise SystemExit("fine-tune weights do not match the recorded SHA-256")

    import torch

    torch.set_num_threads(stage1.THREADS)

    selection = contract.load_json(stage1.SET)
    tools = selection["tools"]
    glosses = contract.load_json(stage1.GLOSSES)["glosses"]
    negation = contract.load_json(stage1.NEGATION)["items"]
    _ids, key_to_id, criteria = contract.build_options(contract.read_only_tools(tools), glosses)
    question = contract.choice_question(criteria)
    allowed = set(key_to_id) - {contract.NONE_ID}
    dangerous = sorted(contract.dangerous_ids(tools))

    answerable = gate.assert_answerable_mix(selection["tasks"], tools)
    answerable_ids = {task["id"] for task in answerable}
    _training, validation = gate.validation_split(gate.load_jsonl(stage1.TRAIN))

    tasks = (
        [{"id": r["id"], "category": r["category"], "prompt": r["state"]["request"],
          "expected": r["expected"], "split": "validation"} for r in validation]
        + [{**t, "split": "eval"} for t in selection["tasks"]]
        + [{**n, "split": "negation"} for n in negation]
    )

    import laya

    agent = laya.load(str(MODEL), device="cpu")

    def ask(task: dict) -> dict:
        started = time.perf_counter()
        result = agent.system_one(
            {"request": task["prompt"]},
            question,
            head_max_len=contract.HEAD_MAX_LEN,
            max_len=contract.MAX_LEN,
        )
        elapsed = (time.perf_counter() - started) * 1000
        usage = result.get("usage") or {}
        if stage1.option_collapse(usage) or usage.get("truncated"):
            raise SystemExit(f"options collapsed or state truncated on {task['id']}")
        answer = result["answers"]["tool"]
        choice, rejected = contract.accept_choice(str(answer.get("choice")), allowed)
        return {
            "id": task["id"], "category": task["category"], "expected": task["expected"],
            "split": task["split"], "choice": choice, "rejected": rejected,
            "confidence": float(answer.get("answer_confidence") or 0),
            "latencyMs": elapsed, "dangerous": dangerous,
        }

    ask(tasks[0])  # warm-up, not timed
    rows = []
    for index, task in enumerate(tasks, start=1):
        rows.append(ask(task))
        if index % 50 == 0 or index == len(tasks):
            print(f"{index}/{len(tasks)}", flush=True)

    valid = [r for r in rows if r["split"] == "validation"]
    weighting = gate.reweight(
        valid,
        gate.target_mix(selection["tasks"], tools),
        text_of=lambda r: next(t["prompt"] for t in tasks if t["id"] == r["id"]),
        expected_of=lambda r: r["expected"],
    )
    threshold, sweep = gate.choose_threshold_weighted(valid, weighting["weights"])

    held = [r for r in rows if r["id"] in answerable_ids]
    adversarial = [r for r in rows if r["split"] == "eval" and r["category"] == "adversarial"]
    negated = [r for r in rows if r["split"] == "negation"]
    result = {name: scored(group, threshold) for name, group in
              (("answerable67", held), ("adversarial", adversarial), ("negation", negated))}
    reference = json.loads(BASELINE67.read_text(encoding="utf-8"))
    base = reference["answerable67"]
    before = stage1b_on(answerable_ids)

    ours, theirs = weak_counts(result["answerable67"]), weak_counts(before)
    checks = {
        "baselineReproducesD-R6": reference["comparableToDR6"] is True,
        "falseWriteZero": all(result[k]["falseWrite"] == 0 for k in result),
        "aboveD-R6": result["answerable67"]["top1"] > base["top1"],
        "aboveStage1b": result["answerable67"]["top1"] > before["top1"],
        "weakCategoriesImprove": all(ours[c] > theirs[c] for c in WEAK),
        "latency": result["answerable67"]["p50Ms"] <= LATENCY_RATIO * base["p50Ms"],
        "negationHolds": result["negation"]["top1"]
        >= NEGATION_MIN_SHARE * result["negation"]["tasks"],
    }
    payload = {
        "status": "measured",
        "gate2": "pass" if all(checks.values()) else "fail",
        "checks": checks,
        "model": str(MODEL), "weightsSha256": WEIGHTS_SHA256,
        "threshold": threshold, "sweep": sweep,
        "weighting": {k: v for k, v in weighting.items() if k not in ("weights", "keys")},
        "validationUnweighted": scored(valid, threshold),
        **result,
        "reference": {"d-r6": {k: base[k] for k in ("top1", "tasks", "falseWrite", "p50Ms")},
                      "stage1b": {"top1": before["top1"], "weak": theirs},
                      "fineTuneWeak": ours},
        "predictions": rows,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"gate2": payload["gate2"], "checks": checks, "threshold": threshold,
                      "top1": result["answerable67"]["top1"], "dR6": base["top1"],
                      "stage1b": before["top1"], "weak": ours, "weakBefore": theirs,
                      "p50": result["answerable67"]["p50Ms"], "dR6p50": base["p50Ms"]},
                     ensure_ascii=False), flush=True)
    return 0 if payload["gate2"] == "pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())
