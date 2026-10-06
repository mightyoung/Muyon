#!/usr/bin/env python3
"""Stage 1b measurement: read-only options, no shortlist, no training.

Fits one global threshold on scripts/laya/train_set.jsonl. The 140-task set,
its adversarial items and the negation set are scored after that fit.

Writes ~/.cache/muyon-eval/stage1b-metrics.json. Does not edit the D-R6
report, does not read .env, and does not start a download (HF offline).
Exit 2 when gate 1b fails or the option list collapses. Exit 3 when another
heavy job is on the machine.
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
TRAIN = HERE / "train_set.jsonl"
OUT = Path(os.path.expanduser("~/.cache/muyon-eval/stage1b-metrics.json"))
BASELINE = Path(os.path.expanduser("~/.cache/muyon-eval/laya-metrics.json"))
CHECKPOINT = "convaiinnovations/laya-multilingual"
REVISION = "1720e3e3357cfe1e281542e223f8273b0890ca34"
THREADS = 4
BATCH_SIZE = 4


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


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def questions_for(criteria: dict[str, str], *, include_noul: bool) -> dict:
    questions = contract.choice_question(criteria)
    if include_noul:
        questions.update(contract.noul_question())
    return questions


def option_collapse(usage: dict) -> dict | None:
    options = (usage or {}).get("options") or {}
    tool = options.get("tool")
    if tool and tool.get("distinct", 0) < tool.get("total", 0):
        return tool
    return None


def predict_all(agent, states: list[dict], questions: dict, batch_size: int) -> tuple[list[dict], int]:
    """Return one result per state. On a memory error, halve the batch and retry that chunk."""
    size = batch_size
    outputs: list[dict] = []
    index = 0
    while index < len(states):
        chunk = states[index : index + size]
        try:
            started = time.perf_counter()
            batch = agent.predict_batch(
                chunk,
                questions,
                batch_size=size,
                sort_by_length=False,
                head_max_len=contract.HEAD_MAX_LEN,
                max_len=contract.MAX_LEN,
            )
            elapsed_ms = (time.perf_counter() - started) * 1000
        except RuntimeError as error:
            if size == 1 or "memory" not in str(error).lower():
                raise
            print(f"batch {size} ran out of memory; retrying at {max(1, size // 2)}", flush=True)
            size = max(1, size // 2)
            continue
        if len(batch) != len(chunk):
            raise RuntimeError(f"predict_batch returned {len(batch)} rows for {len(chunk)} states")
        for item in batch:
            stamped = dict(item)
            stamped["_batchMs"] = elapsed_ms
            stamped["_batchSize"] = len(chunk)
            outputs.append(stamped)
        index += len(chunk)
        done = len(outputs)
        if done == len(chunk) or done % 80 < len(chunk) or done == len(states):
            print(f"predicted {done}/{len(states)} batch={size} {elapsed_ms:.0f} ms", flush=True)
    return outputs, size


def to_row(task: dict, result: dict, allowed: set[str], dangerous: list[str]) -> dict:
    answer = result["answers"]["tool"]
    noul_answer = (result.get("answers") or {}).get("needs_tool") or {}
    raw = str(answer.get("choice"))
    choice, rejected = contract.accept_choice(raw, allowed)
    usage = result.get("usage") or {}
    return {
        "id": task["id"],
        "category": task["category"],
        "expected": task["expected"],
        "split": task["split"],
        "choice": choice,
        "rawChoice": raw,
        "rejected": rejected,
        "confidence": float(answer.get("answer_confidence") or 0),
        "noulPTrue": float(noul_answer.get("noul") or 0),
        "latencyMs": float(result.get("_batchMs") or 0) / max(int(result.get("_batchSize") or 1), 1),
        "truncated": bool(usage.get("truncated")),
        "collapse": option_collapse(usage),
        "dangerous": dangerous,
    }


def effect_of(expected: str, effects: dict[str, str]) -> str:
    if expected == contract.NONE_ID:
        return contract.NONE_ID
    return effects[expected]


def expected_breakdown(rows: list[dict], effects: dict[str, str]) -> dict:
    counts = {"read": 0, "none": 0, "write": 0, "network": 0, "export": 0}
    blocked = []
    for row in rows:
        name = effect_of(row["expected"], effects)
        counts[name] = counts.get(name, 0) + 1
        if name not in (contract.READ_EFFECT, contract.NONE_ID):
            blocked.append(
                {"id": row["id"], "category": row["category"], "expected": row["expected"], "effect": name}
            )
    answerable = counts["read"] + counts["none"]
    return {
        "tasks": len(rows),
        "byEffect": counts,
        "answerableWhenReadOnly": answerable,
        "automaticMisses": len(blocked),
        "automaticMissIds": blocked,
        "note": "A task whose expected tool is write, export or network cannot be a hit: Laya may only return a read tool or none, and abstaining counts as a hit only when expected is none.",
    }


def publish(scored: dict) -> dict:
    rows = scored.pop("rows")
    scored["falseWriteIds"] = [
        {
            "id": row["id"],
            "category": row["category"],
            "choice": row["chosen"],
            "expected": row["expected"],
            "confidence": row["confidence"],
        }
        for row in rows
        if row["falseWrite"]
    ]
    scored["rawDangerousChoices"] = [
        {
            "id": row["id"],
            "category": row["category"],
            "rawChoice": row["rawChoice"],
            "choice": row["choice"],
            "expected": row["expected"],
            "confidence": row["confidence"],
        }
        for row in rows
        if row.get("rawChoice") in set(row["dangerous"])
    ]
    return scored


def score_choice(rows: list[dict], threshold: float) -> dict:
    return publish(contract.apply_threshold(rows, threshold))


def score_noul(rows: list[dict], noul_threshold: float, threshold: float) -> dict:
    return publish(contract.apply_threshold(contract.rewrite_noul(rows, noul_threshold), threshold))


def compact(rows: list[dict], effects: dict[str, str]) -> list[dict]:
    return [
        {
            "id": row["id"],
            "category": row["category"],
            "split": row["split"],
            "expected": row["expected"],
            "expectedEffect": effect_of(row["expected"], effects),
            "choice": row["choice"],
            "rawChoice": row["rawChoice"],
            "rejected": row["rejected"],
            "confidence": row["confidence"],
            "noulPTrue": row["noulPTrue"],
        }
        for row in rows
    ]


def baseline_block() -> dict | None:
    if not BASELINE.is_file():
        return None
    payload = contract.load_json(BASELINE)
    held = payload.get("heldOut") or {}
    return {
        "status": payload.get("status"),
        "threshold": payload.get("threshold"),
        "heldOut": {
            key: held.get(key)
            for key in ("tasks", "top1", "falseWrite", "abstained", "p50Ms", "p95Ms", "byCategory")
        },
    }


def fail_closed(payload: dict, code: int) -> int:
    payload.setdefault("training", "not started")
    write_status(payload)
    print(json.dumps({k: payload[k] for k in payload if k in ("status", "gate1b", "error")}, ensure_ascii=False), flush=True)
    return code


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
    readable = contract.read_only_tools(tools)
    _id_to_key, key_to_id, criteria = contract.build_options(readable, glosses)
    allowed = set(key_to_id) - {contract.NONE_ID}
    dangerous = sorted(contract.dangerous_ids(tools))
    effects = {tool["id"]: tool["effect"] for tool in tools}
    both = questions_for(criteria, include_noul=True)
    choice_only = questions_for(criteria, include_noul=False)

    train_raw = load_jsonl(TRAIN)
    bad_labels = [
        row["id"]
        for row in train_raw
        if row["expected"] != contract.NONE_ID and effects.get(row["expected"]) != contract.READ_EFFECT
    ]
    if bad_labels:
        return fail_closed(
            {
                "status": "not measured",
                "gate1b": "not run",
                "error": f"training rows still label a non-read tool ({len(bad_labels)}); regenerate train_set.jsonl",
                "checkpoint": CHECKPOINT,
                "revision": REVISION,
            },
            2,
        )

    tasks = []
    for row in train_raw:
        tasks.append(
            {
                "id": row["id"],
                "category": row["category"],
                "prompt": row["state"]["request"],
                "expected": row["expected"],
                "split": "train",
            }
        )
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
                "split": "negation",
            }
        )

    import laya
    from importlib.metadata import version

    package = f"laya=={version('laya')}"
    print(
        f"loading {CHECKPOINT} revision {REVISION} offline options={len(criteria)} read_tools={len(readable)}",
        flush=True,
    )
    agent = laya.load(CHECKPOINT, device="cpu", revision=REVISION)
    print(f"loaded revision={getattr(agent, 'revision', None)} threads={torch.get_num_threads()}", flush=True)

    warmup_started = time.perf_counter()
    warmup = agent.predict_batch(
        [{"request": tasks[0]["prompt"]}],
        both,
        batch_size=1,
        sort_by_length=False,
        head_max_len=contract.HEAD_MAX_LEN,
        max_len=contract.MAX_LEN,
    )[0]
    warmup_ms = (time.perf_counter() - warmup_started) * 1000
    collapsed = option_collapse(warmup.get("usage") or {})
    if collapsed:
        return fail_closed(
            {
                "status": "not measured",
                "gate1b": "not run",
                "error": f"option list collapsed on the warmup call: {collapsed}",
                "checkpoint": CHECKPOINT,
                "revision": getattr(agent, "revision", None),
                "package": package,
                "call": {
                    "headMaxLen": contract.HEAD_MAX_LEN,
                    "maxLen": contract.MAX_LEN,
                    "options": len(criteria),
                },
            },
            2,
        )
    print(f"warmup {warmup_ms:.1f} ms options stayed distinct", flush=True)

    states = [{"request": task["prompt"]} for task in tasks]
    raw_results, used_batch = predict_all(agent, states, both, BATCH_SIZE)
    rows = [to_row(task, result, allowed, dangerous) for task, result in zip(tasks, raw_results)]
    collapsed_rows = [row for row in rows if row["collapse"]]
    if collapsed_rows:
        return fail_closed(
            {
                "status": "not measured",
                "gate1b": "not run",
                "error": f"option list collapsed on {collapsed_rows[0]['id']}: {collapsed_rows[0]['collapse']}",
                "collapsed": len(collapsed_rows),
                "checkpoint": CHECKPOINT,
                "revision": getattr(agent, "revision", None),
                "package": package,
            },
            2,
        )
    truncated = [row["id"] for row in rows if row["truncated"]]
    if truncated:
        return fail_closed(
            {
                "status": "not measured",
                "gate1b": "not run",
                "error": f"state truncated on {len(truncated)} rows, first {truncated[0]}",
                "checkpoint": CHECKPOINT,
                "revision": getattr(agent, "revision", None),
                "package": package,
            },
            2,
        )

    train_rows = [row for row in rows if row["split"] == "train"]
    eval_rows = [row for row in rows if row["split"] == "eval"]
    negation_rows = [row for row in rows if row["split"] == "negation"]
    _calibration, held_rows = contract.split_calibration(eval_rows)
    if len(held_rows) != contract.HELD_OUT_TASKS:
        return fail_closed(
            {
                "status": "not measured",
                "gate1b": "not run",
                "error": f"held-out split is {len(held_rows)}, expected {contract.HELD_OUT_TASKS}",
                "checkpoint": CHECKPOINT,
                "revision": getattr(agent, "revision", None),
            },
            2,
        )

    choice_threshold, choice_sweep = contract.choose_threshold(train_rows)
    noul_best, noul_sweep = contract.select_noul_threshold(train_rows)
    without_held = score_choice(held_rows, choice_threshold)
    with_held = score_noul(held_rows, noul_best["noulThreshold"], noul_best["globalThreshold"])
    use_noul = contract.keep_noul(
        without_top1=without_held["top1"],
        with_top1=with_held["top1"],
        with_false_write=with_held["falseWrite"],
    )
    if use_noul:
        kept_name = "noul"
        kept_threshold = noul_best["globalThreshold"]
        kept_noul = noul_best["noulThreshold"]

        def score_kept(group):
            return score_noul(group, kept_noul, kept_threshold)
    else:
        kept_name = "choice-only"
        kept_threshold = choice_threshold
        kept_noul = 0.0

        def score_kept(group):
            return score_choice(group, kept_threshold)

    adversarial_rows = [row for row in eval_rows if row["category"] == "adversarial"]
    held = score_kept(held_rows)
    adversarial = score_kept(adversarial_rows)
    negation_scored = score_kept(negation_rows)
    passed = contract.gate1b(
        held_false_write=held["falseWrite"],
        adversarial_false_write=adversarial["falseWrite"],
        negation_false_write=negation_scored["falseWrite"],
        held_top1=held["top1"],
        held_tasks=held["tasks"],
    )

    # Choice-only sequential latency on the same 93. The batched forward above
    # shares the noul question and is not the D-R6 comparison figure. One
    # warmup call is excluded, then every held-out prompt is timed.
    prompts = {task["id"]: task["prompt"] for task in tasks}
    warmup_choice_started = time.perf_counter()
    agent.system_one(
        {"request": prompts[held_rows[0]["id"]]},
        choice_only,
        head_max_len=contract.HEAD_MAX_LEN,
        max_len=contract.MAX_LEN,
    )
    choice_warmup_ms = (time.perf_counter() - warmup_choice_started) * 1000
    choice_latency = []
    for row in held_rows:
        started = time.perf_counter()
        agent.system_one(
            {"request": prompts[row["id"]]},
            choice_only,
            head_max_len=contract.HEAD_MAX_LEN,
            max_len=contract.MAX_LEN,
        )
        choice_latency.append((time.perf_counter() - started) * 1000)
    print(
        f"choice-only latency p50={contract.percentile(choice_latency, 0.50):.1f} ms "
        f"over {len(choice_latency)} held-out calls",
        flush=True,
    )

    reason = (
        f"held-out top-1 with noul is {with_held['top1']} and without noul is {without_held['top1']}; "
        f"{'kept noul because the two-step score is strictly higher and false write stayed 0' if use_noul else 'dropped noul because it did not strictly raise held-out top-1'}"
    )
    payload = {
        "status": "measured",
        "gate1b": "pass" if passed else "fail",
        "package": package,
        "checkpoint": CHECKPOINT,
        "revision": getattr(agent, "revision", None),
        "threads": torch.get_num_threads(),
        "call": {
            "api": "predict_batch over every read-only tool plus none; no shortlist",
            "headMaxLen": contract.HEAD_MAX_LEN,
            "maxLen": contract.MAX_LEN,
            "batchSize": used_batch,
            "requestedBatchSize": BATCH_SIZE,
            "sortByLength": False,
            "questions": ["needs_tool", "tool"],
            "optionCount": len(criteria),
            "readToolIds": sorted(allowed),
            "excludedEffect": "write, export and network are not offered; a named one is recorded as rawChoice and scored as none",
            "device": "cpu",
            "offline": True,
            "warmupExcludedMs": round(warmup_ms, 3),
        },
        "fit": {
            "split": "scripts/laya/train_set.jsonl prompts and expected labels only. Questions are rebuilt from every read-only tool. The 140, adversarial items and negation are not used to fit.",
            "rows": len(train_rows),
            "rule": "one global threshold: zero false write/external, then higher top-1, then a higher threshold. No category or language buckets.",
            "choiceOnlyThreshold": choice_threshold,
            "choiceOnlySweep": choice_sweep,
            "noulFit": noul_best,
            "noulSweep": noul_sweep,
            "trainChoiceOnly": score_choice(train_rows, choice_threshold),
            "trainWithNoul": score_noul(train_rows, noul_best["noulThreshold"], noul_best["globalThreshold"]),
        },
        "decision": {
            "kept": kept_name,
            "threshold": kept_threshold,
            "noulThreshold": kept_noul,
            "reason": reason,
        },
        "withoutNoul": {"heldOut": without_held},
        "withNoul": {
            "noulThreshold": noul_best["noulThreshold"],
            "globalThreshold": noul_best["globalThreshold"],
            "heldOut": with_held,
        },
        "heldOut": held,
        "heldOutExpected": expected_breakdown(held_rows, effects),
        "adversarial": adversarial,
        "negation": negation_scored,
        "predictions": compact(eval_rows + negation_rows, effects),
        "latency": {
            "heldOutChoiceOnlyP50Ms": round(contract.percentile(choice_latency, 0.50), 3),
            "heldOutChoiceOnlyP95Ms": round(contract.percentile(choice_latency, 0.95), 3),
            "choiceOnlyWarmupExcludedMs": round(choice_warmup_ms, 3),
            "note": "Choice-only p50 is 93 sequential system_one calls with the tool question only. latencyMs on the scored blocks is the batched forward that also asks noul, divided by the batch size, and is not the D-R6 comparison.",
        },
        "baseline": baseline_block(),
        "training": "not started",
    }
    write_status(payload)
    print(
        f"GATE1b {payload['gate1b']} kept={kept_name} threshold={kept_threshold} noul={kept_noul} "
        f"held top1={held['top1']}/{held['tasks']} "
        f"without={without_held['top1']} with={with_held['top1']} "
        f"falseWrite={held['falseWrite']} adversarial={adversarial['falseWrite']} "
        f"negation={negation_scored['falseWrite']} "
        f"answerable={payload['heldOutExpected']['answerableWhenReadOnly']} "
        f"p50={payload['latency']['heldOutChoiceOnlyP50Ms']}",
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
                "gate1b": "not run",
                "error": f"{type(error).__name__}: {error}",
                "checkpoint": CHECKPOINT,
                "revision": REVISION,
                "training": "not started",
            }
        )
        raise
