"""Synthetic tool-selection decisions for Kaggle fine-tuning.

Positive requests are natural wording in the tool's own domain. They must not
quote the option description. The 140-task file and the negation set are
evaluation only. A few tools are absent from every option list and every label.
A's hand-written supplement is appended, with gold filled in.
"""

from __future__ import annotations

import json
import random
import re
from pathlib import Path

import natural_bank
import stage1_contract as contract
import stage2_threshold as gate

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SELECTION = ROOT / "apps/muyon/lib/assistant/selection_eval/selection_set.json"
SEED = 20261007
NEAR_DUPLICATE = 0.5
DESCRIPTION_JACCARD = 0.4
DESCRIPTION_SPAN = 8
HELD_OUT_TOOLS = (
    "inquiry.project_budget",
    "ocr.recognize",
    "transfer.export",
    "embedding.search",
)
PLAN = {
    "natural": 360,
    "english": 300,
    "mixed": 300,
    "negate-one-ask-another": 300,
    "urgent-read": 300,
    "misleading": 200,
    "none": 300,
    "ambiguous": 120,
    "urgent-write": 180,
    # Appended last so the earlier categories draw the same rows as before.
    "negate-only": 300,
}
_SPACE = re.compile(r"\s+")


def _folded(text: str) -> str:
    return _SPACE.sub("", text.lower())


def bigram_jaccard(left: str, right: str) -> float:
    def grams(text: str) -> set[str]:
        folded = _folded(text)
        if len(folded) < 2:
            return {folded} if folded else set()
        return {folded[i : i + 2] for i in range(len(folded) - 1)}

    one, two = grams(left), grams(right)
    if not one and not two:
        return 1.0
    if not one or not two:
        return 0.0
    return len(one & two) / len(one | two)


def longest_common_substring(left: str, right: str) -> int:
    a, b = _folded(left), _folded(right)
    best = 0
    prev = [0] * (len(b) + 1)
    for char in a:
        cur = [0] * (len(b) + 1)
        for index, other in enumerate(b):
            if char == other:
                cur[index + 1] = prev[index] + 1
                if cur[index + 1] > best:
                    best = cur[index + 1]
        prev = cur
    return best


_MASKS: list[str] | None = None


def _masked(text: str) -> str:
    """Collapse entities, codes and pinyin so a template counts as one pattern."""
    global _MASKS
    if _MASKS is None:
        _MASKS = natural_bank.mask_entities()
    folded = text
    for ent in _MASKS:
        if ent in folded:
            folded = folded.replace(ent, "○")
    folded = re.sub(r"[A-Za-z0-9]+", "X", folded)
    folded = re.sub(r"[○X]+", "○", folded)
    return _SPACE.sub("", folded)


def copies_option_text(request: str, option_text: str) -> bool:
    return (
        bigram_jaccard(request, option_text) >= DESCRIPTION_JACCARD
        or longest_common_substring(request, option_text) >= DESCRIPTION_SPAN
    )


def assert_no_description_copy(rows: list[dict]) -> None:
    for row in rows:
        request = row["state"]["request"]
        expected = row["expected"]
        shown = row["questions"]["tool"]["criteria"].get(expected, "")
        if copies_option_text(request, shown):
            jac = bigram_jaccard(request, shown)
            span = longest_common_substring(request, shown)
            raise ValueError(f"{row['id']} copies its option text jaccard={jac:.3f} lcs={span}")


def _too_close(prompt: str, eval_grams: list[set[str]], seen: set[str]) -> bool:
    folded = contract.normalize_text(prompt)
    if not folded or folded in seen:
        return True
    grams = contract.char_ngrams(prompt)
    if any(contract.jaccard(grams, other) >= NEAR_DUPLICATE for other in eval_grams):
        return True
    return False


def _with_gold(row: dict) -> dict:
    criteria = row["questions"]["tool"]["criteria"]
    expected = row["expected"]
    if expected not in criteria:
        raise RuntimeError(f"{row['id']} gold option missing")
    item = dict(row)
    item["gold"] = {
        "tool": {
            "probabilities": {key: 1.0 if key == expected else 0.0 for key in criteria}
        }
    }
    return item


def _example(rng: random.Random, tool_ids: list[str], full: dict[str, str], expected: str, prompt: str, category: str, index: int, full_set: bool) -> dict:
    if full_set:
        keys = list(tool_ids)
    else:
        others = [tool_id for tool_id in tool_ids if tool_id != expected]
        width = rng.randint(4, 7)
        keys = rng.sample(others, k=min(width, len(others)))
        if expected != contract.NONE_ID:
            keys.append(expected)
    if contract.NONE_ID not in keys:
        keys.append(contract.NONE_ID)
    rng.shuffle(keys)
    criteria = {key: full[key] for key in keys}
    row = {
        "id": f"train-{index:04d}",
        "category": category,
        "expected": expected,
        "state": {"request": prompt},
        "questions": {
            "tool": {
                "type": "choice",
                "instructions": contract.CHOICE_INSTRUCTIONS,
                "criteria": criteria,
            }
        },
    }
    return _with_gold(row)


def _supplement_rows(full: dict[str, str]) -> tuple[list[dict], list[str]]:
    """A's seed stays on disk. Rows that quote the shown option text are left out."""
    path = HERE / "train_supplement_a.jsonl"
    rows = []
    skipped = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        criteria = row["questions"]["tool"]["criteria"]
        missing = [key for key in criteria if key not in full]
        if missing:
            raise RuntimeError(f"{row['id']} has an option that is not trainable: {missing}")
        # Keep A's wording and option subset. Refresh the text from the same glosses.
        row["questions"]["tool"]["criteria"] = {key: full[key] for key in criteria}
        shown = row["questions"]["tool"]["criteria"][row["expected"]]
        if copies_option_text(row["state"]["request"], shown):
            skipped.append(row["id"])
            continue
        rows.append(_with_gold(row))
    return rows, skipped


def generate(selection: dict, glosses: dict[str, str], eval_prompts: list[str]) -> tuple[list[dict], dict]:
    eval_grams = [contract.char_ngrams(prompt) for prompt in eval_prompts]
    tools = selection["tools"]
    known = {tool["id"] for tool in tools}
    missing = [tool_id for tool_id in HELD_OUT_TOOLS if tool_id not in known]
    if missing:
        raise ValueError(f"held-out tools are not registered: {missing}")
    option_tools = [
        tool for tool in tools if tool["effect"] == contract.READ_EFFECT and tool["id"] not in HELD_OUT_TOOLS
    ]
    _id_to_key, _key_to_id, full = contract.build_options(option_tools, glosses)
    tool_ids = [tool["id"] for tool in option_tools]
    by_id = {tool["id"]: tool for tool in option_tools}
    rng = random.Random(SEED)
    seen = {contract.normalize_text(prompt) for prompt in eval_prompts}
    supplement, supplement_skipped = _supplement_rows(full)
    for row in supplement:
        if row["expected"] in HELD_OUT_TOOLS:
            raise RuntimeError(f"{row['id']} labels a held-out tool")
        seen.add(contract.normalize_text(row["state"]["request"]))
    rows: list[dict] = []
    rejected_eval = 0
    rejected_copy = 0

    def accept(category: str, expected: str, prompt: str) -> bool:
        nonlocal rejected_eval, rejected_copy
        option_text = full[expected]
        if copies_option_text(prompt, option_text):
            rejected_copy += 1
            return False
        if _too_close(prompt, eval_grams, seen):
            rejected_eval += 1
            return False
        seen.add(contract.normalize_text(prompt))
        rows.append(
            _example(
                rng,
                tool_ids,
                full,
                expected,
                prompt,
                category,
                len(rows) + 1,
                full_set=(len(rows) % 5) < 3,
            )
        )
        return True

    for category, target in PLAN.items():
        guard = 0
        draw = natural_bank.DRAWS[category]
        while sum(row["category"] == category for row in rows) < target:
            guard += 1
            if guard > target * 80:
                got = sum(row["category"] == category for row in rows)
                raise RuntimeError(
                    f"could not fill {category} got={got} rejected_copy={rejected_copy} "
                    f"rejected_eval={rejected_eval}"
                )
            prompt, expected = draw(rng)
            accept(category, expected, prompt)

    rows.extend(supplement)

    generated_by_category = {category: 0 for category in PLAN}
    for row in rows:
        if row["id"].startswith("train-"):
            generated_by_category[row["category"]] += 1
    by_category = {}
    by_label = {"read": 0, "none": 0}
    for row in rows:
        by_category[row["category"]] = by_category.get(row["category"], 0) + 1
        by_label["none" if row["expected"] == contract.NONE_ID else "read"] += 1
    full_width = len(tool_ids) + 1
    full_rows = sum(len(row["questions"]["tool"]["criteria"]) == full_width for row in rows)
    strata: dict[str, int] = {}
    for row in rows:
        key = gate.stratum_key(row["expected"], row["state"]["request"])
        strata[key] = strata.get(key, 0) + 1
    held_text = []
    for tool in tools:
        if tool["id"] in HELD_OUT_TOOLS:
            held_text.append(tool["description"])
            held_text.append(glosses[tool["id"]])
    leaked = []
    for row in rows:
        blob = json.dumps(row["questions"], ensure_ascii=False)
        if row["expected"] in HELD_OUT_TOOLS or any(piece and piece in blob for piece in held_text):
            leaked.append(row["id"])
    overlaps = [contract.max_ngram_jaccard(row["state"]["request"], eval_prompts) for row in rows]
    copy_jaccard = [
        bigram_jaccard(row["state"]["request"], row["questions"]["tool"]["criteria"][row["expected"]])
        for row in rows
    ]
    copy_span = [
        longest_common_substring(row["state"]["request"], row["questions"]["tool"]["criteria"][row["expected"]])
        for row in rows
    ]
    report = {
        "seed": SEED,
        "items": len(rows),
        "generatedByCategory": generated_by_category,
        "byCategory": by_category,
        "byLabel": by_label,
        "fullOptionRows": full_rows,
        "fullOptionWidth": full_width,
        "distinctRequests": len({contract.normalize_text(row["state"]["request"]) for row in rows}),
        "heldOutTools": list(HELD_OUT_TOOLS),
        "rejectedAsNearDuplicate": rejected_eval,
        "rejectedDescriptionCopies": rejected_copy,
        "exactEvalMatches": 0,
        "maxEvalJaccard": round(max(overlaps), 4) if overlaps else 0,
        "nearDuplicatesAtOrAbove0.5": sum(value >= NEAR_DUPLICATE for value in overlaps),
        "maxDescriptionBigramJaccard": round(max(copy_jaccard), 4) if copy_jaccard else 0,
        "maxDescriptionCommonSpan": max(copy_span) if copy_span else 0,
        "descriptionCopiesAtOrAbove0.4": sum(value >= DESCRIPTION_JACCARD for value in copy_jaccard),
        "descriptionSpansAtOrAbove8": sum(value >= DESCRIPTION_SPAN for value in copy_span),
        "heldOutLeaks": leaked,
        "trainableTools": sorted(by_id),
        "supplementRows": len(supplement),
        "supplementSkippedAsDescriptionCopy": supplement_skipped,
        "byStratum": dict(sorted(strata.items())),
        "distinctMaskedPatterns": len({_masked(row["state"]["request"]) for row in rows}),
        "evalSources": [
            "apps/muyon/lib/assistant/selection_eval/selection_set.json",
            "scripts/laya/negation_set.json",
        ],
        "note": "Positives do not quote the option text. A's supplement is included once. The 140-task set and the negation set are not training rows.",
    }
    return rows, report


def eval_prompts() -> list[str]:
    selection = contract.load_json(SELECTION)
    negation = contract.load_json(HERE / "negation_set.json")
    return [task["prompt"] for task in selection["tasks"]] + [
        item["prompt"] for item in negation["items"]
    ]


def main() -> None:
    selection = contract.load_json(SELECTION)
    glosses = contract.load_json(HERE / "glosses.json")["glosses"]
    rows, report = generate(selection, glosses, eval_prompts())
    failed = (
        report["nearDuplicatesAtOrAbove0.5"]
        or report["heldOutLeaks"]
        or report["items"] < 1000
        or report["descriptionCopiesAtOrAbove0.4"]
        or report["descriptionSpansAtOrAbove8"]
        or report["fullOptionRows"] * 2 < report["items"]
        or report["distinctRequests"] != report["items"]
    )
    if failed:
        raise SystemExit(f"training set failed its own checks: {json.dumps(report, ensure_ascii=False)}")
    (HERE / "train_set.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )
    (HERE / "train_overlap.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {report['items']} rows maxJaccard={report['maxEvalJaccard']} "
        f"descJ={report['maxDescriptionBigramJaccard']} span={report['maxDescriptionCommonSpan']} "
        f"full={report['fullOptionRows']} labels={report['byLabel']}"
    )


if __name__ == "__main__":
    main()
