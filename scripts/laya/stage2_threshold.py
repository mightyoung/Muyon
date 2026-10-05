"""Stage-2 decision threshold. No model, no network, no .env.

The threshold is fit on a validation split carved from the synthetic training
rows. Those rows are re-weighted so the read-only vs none mix, and the
language mix, match the 67 held-out tasks a read-only selector can answer.
The 140-task file and the negation set are not fit data. A language that the
training split does not contain stays unmatched and is reported.
"""

from __future__ import annotations

import json
import re
from collections import Counter

import stage1_contract as contract

VALIDATION_MODULUS = 5
ANSWERABLE_HELD_OUT = 67
ANSWERABLE_READ = 49
ANSWERABLE_NONE = 18
_HAN = re.compile(r"[\u4e00-\u9fff]")
_LAT = re.compile(r"[A-Za-z]")


def request_language(text: str) -> str:
    """Script mix of the request the model sees. Categories are not languages."""
    han = len(_HAN.findall(text))
    lat = len(_LAT.findall(text))
    if han and lat:
        return "mixed"
    if han:
        return "zh"
    return "en"


def decision_label(expected: str) -> str:
    return "none" if expected == contract.NONE_ID else "read"


def stratum_key(expected: str, text: str) -> str:
    return f"{decision_label(expected)}|{request_language(text)}"


def load_jsonl(path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def validation_split(rows: list[dict], modulus: int = VALIDATION_MODULUS):
    """Sorted id. Index divisible by modulus is withheld from Kaggle training."""
    ordered = sorted(rows, key=lambda row: row["id"])
    validation = [row for index, row in enumerate(ordered) if index % modulus == 0]
    training = [row for index, row in enumerate(ordered) if index % modulus != 0]
    return training, validation


def answerable_held_out(tasks: list[dict], tools: list[dict]) -> list[dict]:
    effects = {tool["id"]: tool["effect"] for tool in tools}
    _calibration, held = contract.split_calibration(tasks)
    kept = []
    for task in held:
        expected = task["expected"]
        effect = "none" if expected == contract.NONE_ID else effects.get(expected)
        if effect in {contract.READ_EFFECT, "none"}:
            kept.append(task)
    return kept


def mix_counts(pairs: list[tuple[str, str]]) -> dict[str, int]:
    counts = Counter(stratum_key(expected, text) for expected, text in pairs)
    return dict(sorted(counts.items()))


def target_mix(tasks: list[dict], tools: list[dict]) -> dict[str, int]:
    rows = answerable_held_out(tasks, tools)
    return mix_counts([(row["expected"], row["prompt"]) for row in rows])


def reweight(validation_rows: list[dict], target_counts: dict[str, int], *, text_of, expected_of) -> dict:
    """Weight each validation row by target_count / source_count on its stratum.

    Target strata with no validation row are unmatched and left out. Their
    share is not quietly given to another language. Source strata absent from
    the target get weight 0.
    """
    source_pairs = [(expected_of(row), text_of(row)) for row in validation_rows]
    source_counts = mix_counts(source_pairs)
    supported = [
        key
        for key, count in target_counts.items()
        if count > 0 and source_counts.get(key, 0) > 0
    ]
    unmatched = {
        key: count
        for key, count in target_counts.items()
        if count > 0 and key not in supported
    }
    target_mass = sum(target_counts[key] for key in supported)
    weights = []
    keys = []
    for expected, text in source_pairs:
        key = stratum_key(expected, text)
        keys.append(key)
        source_count = source_counts.get(key, 0)
        if key not in supported or target_mass == 0 or source_count == 0:
            weights.append(0.0)
            continue
        weights.append(target_counts[key] / source_count)
    dropped = {
        key: count
        for key, count in source_counts.items()
        if key not in supported and count > 0
    }
    shares = {key: target_counts[key] / target_mass for key in supported} if target_mass else {}
    return {
        "targetCounts": target_counts,
        "sourceCounts": source_counts,
        "supported": supported,
        "unmatchedTarget": unmatched,
        "droppedSource": dropped,
        "renormalizedTargetShare": shares,
        "weights": weights,
        "keys": keys,
    }


def choose_threshold_weighted(rows: list[dict], weights: list[float]):
    """Zero unweighted false writes, then higher weighted top-1, then a higher threshold."""
    if len(rows) != len(weights):
        raise ValueError("one weight per row")
    total = sum(weights)
    if not rows or total <= 0:
        return 1.0, []
    best = None
    sweep = []
    for step in range(21):
        threshold = round(step / 20, 2)
        judgments = [contract.judge_row(row, threshold) for row in rows]
        false_write = sum(int(item["falseWrite"]) for item in judgments)
        weighted_hits = sum(weight * int(item["hit"]) for weight, item in zip(weights, judgments))
        point = {
            "threshold": threshold,
            "top1": weighted_hits / total,
            "weightedHits": weighted_hits,
            "weight": total,
            "falseWrite": false_write,
        }
        sweep.append(point)
        candidate = (false_write == 0, weighted_hits, threshold)
        current = None if best is None else (
            best["falseWrite"] == 0,
            best["weightedHits"],
            best["threshold"],
        )
        if current is None or candidate > current:
            best = point
    return best["threshold"], sweep


def assert_read_only_targets(rows: list[dict], tools: list[dict], held_out: set[str]) -> None:
    effects = {tool["id"]: tool["effect"] for tool in tools}
    read_ids = {tool_id for tool_id, effect in effects.items() if effect == contract.READ_EFFECT}
    for row in rows:
        expected = row["expected"]
        if expected in held_out:
            raise ValueError(f"{row['id']} labels a held-out tool")
        if expected != contract.NONE_ID and expected not in read_ids:
            raise ValueError(f"{row['id']} target {expected} is not read-only or none")
        for key in row["questions"]["tool"]["criteria"]:
            if key == contract.NONE_ID:
                continue
            if key in held_out or effects.get(key) != contract.READ_EFFECT:
                raise ValueError(f"{row['id']} offers {key}")


def assert_overlap(report: dict) -> None:
    if report.get("exactEvalMatches") != 0:
        raise ValueError("training copies an evaluation prompt")
    if report.get("nearDuplicatesAtOrAbove0.5") != 0:
        raise ValueError("training has a near duplicate of an evaluation prompt")
    jaccard = report.get("maxEvalJaccard")
    if not isinstance(jaccard, (int, float)) or jaccard >= 0.5:
        raise ValueError(f"maxEvalJaccard {jaccard} is not under 0.5")
    if report.get("heldOutLeaks"):
        raise ValueError("held-out tool leaked into training")


def assert_answerable_mix(tasks: list[dict], tools: list[dict]) -> list[dict]:
    rows = answerable_held_out(tasks, tools)
    labels = Counter(decision_label(row["expected"]) for row in rows)
    if len(rows) != ANSWERABLE_HELD_OUT or labels["read"] != ANSWERABLE_READ or labels["none"] != ANSWERABLE_NONE:
        raise ValueError(
            f"answerable held-out is {len(rows)} read={labels['read']} none={labels['none']}, expected 67/49/18"
        )
    return rows
