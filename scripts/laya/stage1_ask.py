#!/usr/bin/env python3
"""Stage 1 measurement: better questions, no training.

Writes ~/.cache/muyon-eval/stage1-metrics.json only. Does not edit the D-R6
report, does not read .env, and does not start a download (HF offline).
Exit 2 when gate 1 fails. Exit 3 when another heavy job is on the machine.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

os.environ["LAYA_THREADS"] = "4"
os.environ["OMP_NUM_THREADS"] = "4"
os.environ["MKL_NUM_THREADS"] = "4"
os.environ["TORCH_NUM_THREADS"] = "4"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
os.environ["LAYA_DEVICE"] = "cpu"
os.environ["HF_HOME"] = os.path.expanduser("~/.cache/muyon-eval/hf")
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import stage1_contract as contract  # noqa: E402

ROOT = HERE.parents[1]
SET = ROOT / "apps/muyon/lib/assistant/selection_eval/selection_set.json"
GLOSSES = HERE / "glosses.json"
NEGATION = HERE / "negation_set.json"
OUT = Path(os.path.expanduser("~/.cache/muyon-eval/stage1-metrics.json"))
BASELINE = Path(os.path.expanduser("~/.cache/muyon-eval/laya-metrics.json"))
CHECKPOINT = "convaiinnovations/laya-multilingual"
REVISION = "1720e3e3357cfe1e281542e223f8273b0890ca34"
THREADS = 4


def other_heavy_jobs() -> list[str]:
    listed = subprocess.run(
        ["ps", "-ax", "-o", "pid=,command="],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    # The launching shell's command line contains this file's name. Skipping
    # that parent keeps a wrapper from looking like a second measurement.
    skip = {str(os.getpid()), str(os.getppid())}
    hits = []
    for line in listed.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        pid, _, _command = stripped.partition(" ")
        if pid in skip:
            continue
        if any(token in stripped for token in ("flutter_tester", "scripts/verify.sh", "stage1_ask.py")):
            hits.append(stripped)
    return hits


def write_status(payload: dict) -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def mapped_choice(answer: dict, key_to_id: dict[str, str]) -> str:
    raw = answer.get("choice")
    if raw in key_to_id:
        return key_to_id[raw]
    return str(raw)


def main() -> int:
    busy = other_heavy_jobs()
    if busy:
        print("machine busy; not loading Laya", flush=True)
        for line in busy:
            print(line, flush=True)
        return 3

    import torch

    torch.set_num_threads(THREADS)
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError as error:
        print(f"interop threads unchanged: {error}", flush=True)

    selection = contract.load_json(SET)
    glosses = contract.load_json(GLOSSES)["glosses"]
    negation = contract.load_json(NEGATION)["items"]
    tools = selection["tools"]
    contract.validate_negation(negation, tools, [task["prompt"] for task in selection["tasks"]])
    dangerous = sorted(contract.dangerous_ids(tools))
    id_to_key, key_to_id, criteria = contract.build_options(tools, glosses)
    question = contract.choice_question(criteria)
    noul = contract.noul_question()

    import laya
    from importlib.metadata import version
    from laya.shortlist import cached_embed_fn, embed_fn_from_agent, predict_shortlist

    package = f"laya=={version('laya')}"
    print(f"loading {CHECKPOINT} revision {REVISION} offline", flush=True)
    agent = laya.load(CHECKPOINT, device="cpu", revision=REVISION)
    embed_fn = cached_embed_fn(embed_fn_from_agent(agent, max_length=256, batch_size=16))
    print(
        f"loaded revision={getattr(agent, 'revision', None)} threads={torch.get_num_threads()} "
        f"labels={len(criteria)} shortlist_k={contract.SHORTLIST_K}",
        flush=True,
    )

    def ask(prompt: str) -> dict:
        state = {"request": prompt}
        noul_started = time.perf_counter()
        noul_result = agent.system_one(
            state,
            noul,
            head_max_len=contract.HEAD_MAX_LEN,
            max_len=contract.MAX_LEN,
        )
        noul_ms = (time.perf_counter() - noul_started) * 1000
        noul_answer = noul_result["answers"]["needs_tool"]
        choice_started = time.perf_counter()
        result = predict_shortlist(
            agent,
            state,
            question,
            embed_fn,
            k=contract.SHORTLIST_K,
            head_max_len=contract.HEAD_MAX_LEN,
            max_len=contract.MAX_LEN,
        )
        meta = result["shortlist"]["tool"]
        pinned = False
        if not meta["passthrough"] and "opt00" not in meta["labels"]:
            pinned = True
            kept = [label for label in meta["labels"] if label != "opt00"][: contract.SHORTLIST_K - 1]
            reduced = contract.choice_question(
                {"opt00": criteria["opt00"], **{label: criteria[label] for label in kept}}
            )
            result = agent.system_one(
                state,
                reduced,
                head_max_len=contract.HEAD_MAX_LEN,
                max_len=contract.MAX_LEN,
            )
        choice_ms = (time.perf_counter() - choice_started) * 1000
        answer = result["answers"]["tool"]
        usage = result.get("usage") or {}
        return {
            "choice": mapped_choice(answer, key_to_id),
            "confidence": float(answer.get("answer_confidence") or 0),
            "noulPTrue": float(noul_answer.get("noul") or 0),
            "latencyMs": noul_ms + choice_ms,
            "choiceLatencyMs": choice_ms,
            "noulLatencyMs": noul_ms,
            "truncated": bool(usage.get("truncated")),
            "shortlist": {
                "passthrough": bool(meta["passthrough"]),
                "k": meta["k"],
                "n": meta["n"],
                "keptNone": "opt00" in meta["labels"],
                "pinnedNone": pinned,
            },
            "keptExpectedKey": None,
            "_meta_labels": list(meta["labels"]),
        }

    tasks = []
    for task in selection["tasks"]:
        tasks.append(
            {
                "id": task["id"],
                "category": task["category"],
                "prompt": task["prompt"],
                "expected": task["expected"],
                "split": "eval",
            }
        )
    for item in negation:
        tasks.append(
            {
                "id": item["id"],
                "category": item["category"],
                "prompt": item["prompt"],
                "expected": item["expected"],
                "tempting": item["tempting"],
                "split": "negation",
            }
        )

    warmup = ask(tasks[0]["prompt"])
    print(f"warmup {warmup['latencyMs']:.1f} ms choice={warmup['choice']}", flush=True)

    raw = []
    for index, task in enumerate(tasks, start=1):
        answer = ask(task["prompt"])
        expected_key = id_to_key.get(task["expected"])
        labels = answer.pop("_meta_labels")
        answer.pop("keptExpectedKey")
        raw.append(
            {
                "id": task["id"],
                "category": task["category"],
                "expected": task["expected"],
                "split": task["split"],
                "tempting": task.get("tempting"),
                "choice": answer["choice"],
                "confidence": answer["confidence"],
                "noulPTrue": answer["noulPTrue"],
                "latencyMs": answer["latencyMs"],
                "choiceLatencyMs": answer["choiceLatencyMs"],
                "noulLatencyMs": answer["noulLatencyMs"],
                "truncated": answer["truncated"],
                "dangerous": dangerous,
                "shortlist": {
                    **answer["shortlist"],
                    "keptExpected": expected_key in labels,
                },
            }
        )
        if index == 1 or index % 20 == 0 or index == len(tasks):
            print(
                f"{index}/{len(tasks)} {task['id']} -> {answer['choice']} "
                f"p={answer['confidence']:.3f} noul={answer['noulPTrue']:.3f} "
                f"{answer['latencyMs']:.0f} ms",
                flush=True,
            )

    eval_rows = [row for row in raw if row["split"] == "eval"]
    negation_rows = [row for row in raw if row["split"] == "negation"]
    calibration_rows, held_rows = contract.split_calibration(eval_rows)
    best, sweep = contract.select_noul_threshold(calibration_rows)
    noul_threshold = best["noulThreshold"]
    global_threshold = best["globalThreshold"]
    by_category = best["byCategory"]

    def finish(rows):
        rewritten = contract.rewrite_noul(rows, noul_threshold)
        scored = contract.apply_category_thresholds(rewritten, global_threshold, by_category)
        failures = [
            {
                "id": row["id"],
                "category": row["category"],
                "choice": row["chosen"],
                "expected": row["expected"],
                "confidence": row["confidence"],
            }
            for row in scored.pop("rows")
            if row["falseWrite"]
        ]
        scored["falseWriteIds"] = failures
        return scored

    held = finish(held_rows)
    adversarial_rows = [row for row in eval_rows if row["category"] == "adversarial"]
    adversarial = finish(adversarial_rows)
    negation_scored = finish(negation_rows)
    passed = contract.gate1(
        held_false_write=held["falseWrite"],
        adversarial_false_write=adversarial["falseWrite"],
        negation_false_write=negation_scored["falseWrite"],
    )
    choice_only_latency = [
        row["choiceLatencyMs"] for row in held_rows
    ]
    baseline = None
    if BASELINE.is_file():
        baseline_payload = contract.load_json(BASELINE)
        baseline = {
            "status": baseline_payload.get("status"),
            "threshold": baseline_payload.get("threshold"),
            "heldOut": {
                key: (baseline_payload.get("heldOut") or {}).get(key)
                for key in ("tasks", "top1", "falseWrite", "abstained", "p50Ms", "p95Ms", "byCategory")
            },
        }
    shortlist_kept = sum(int(row["shortlist"]["keptExpected"]) for row in eval_rows)
    payload = {
        "status": "measured",
        "gate1": "pass" if passed else "fail",
        "package": package,
        "checkpoint": CHECKPOINT,
        "revision": getattr(agent, "revision", None),
        "threads": torch.get_num_threads(),
        "call": {
            "api": "noul system_one, then laya.shortlist.predict_shortlist",
            "headMaxLen": contract.HEAD_MAX_LEN,
            "maxLen": contract.MAX_LEN,
            "shortlistK": contract.SHORTLIST_K,
            "embed": "cached mean-pool of the loaded checkpoint encoder; no second model",
            "nonePinnedWhenDropped": True,
            "device": "cpu",
            "offline": True,
            "warmupExcludedMs": round(warmup["latencyMs"], 3),
        },
        "fit": {
            "split": "sorted task id, index % 3 == 0, on the 140 only; negation is not used to fit",
            "rule": "zero false write/external, then higher top-1, then higher noul cut; per-category choice thresholds with the same rule",
            "noulThreshold": noul_threshold,
            "globalThreshold": global_threshold,
            "byCategory": by_category,
            "sweep": sweep,
            "calibration": finish(calibration_rows),
        },
        "heldOut": held,
        "adversarial": adversarial,
        "negation": negation_scored,
        "shortlistRecall": {
            "evalExpectedKept": shortlist_kept,
            "evalTasks": len(eval_rows),
            "passthrough": sum(int(row["shortlist"]["passthrough"]) for row in raw),
            "pinnedNone": sum(int(row["shortlist"]["pinnedNone"]) for row in raw),
        },
        "latency": {
            "heldOutChoiceOnlyP50Ms": round(contract.percentile(choice_only_latency, 0.50), 3),
            "note": "latencyMs on heldOut includes the noul call. choice-only p50 is the comparable D-R6 figure when the fitted noul cut is 0.",
        },
        "baseline": baseline,
        "training": "not started",
    }
    write_status(payload)
    print(
        f"GATE1 {payload['gate1']} noul={noul_threshold} global={global_threshold} "
        f"held top1={held['top1']}/{held['tasks']} falseWrite={held['falseWrite']} "
        f"adversarial falseWrite={adversarial['falseWrite']} "
        f"negation falseWrite={negation_scored['falseWrite']} "
        f"p50={held['p50Ms']}",
        flush=True,
    )
    return 0 if passed else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as error:
        write_status(
            {
                "status": "not measured",
                "gate1": "not run",
                "error": f"{type(error).__name__}: {error}",
                "checkpoint": CHECKPOINT,
                "revision": REVISION,
                "training": "not started",
            }
        )
        raise
