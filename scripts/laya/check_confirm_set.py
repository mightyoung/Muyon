#!/usr/bin/env python3
"""One-off confirmation-set checks (E10). Standard library only, no model.

Compares every prompt of `confirm_set.json` with the existing question sets
(selection set, negation set, training rows) only through similarity scores:
it never prints their text. It also checks category counts, language mix,
`expected` validity and id uniqueness, and compares each expected tool's
English gloss with the prompt.

Run:
    python3 scripts/laya/check_confirm_set.py

Prints PASS and exits 0 when everything passes; otherwise prints FAIL with the
offending item ids and scores and exits 1.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from stage1_contract import max_ngram_jaccard  # noqa: E402
from stage2_data import bigram_jaccard, longest_common_substring  # noqa: E402

ROOT = HERE.parents[1]
SELECTION = ROOT / "apps/muyon/lib/assistant/selection_eval/selection_set.json"
CONFIRM = HERE / "confirm_set.json"
NEGATION = HERE / "negation_set.json"
TRAIN = HERE / "train_set.jsonl"
SUPPLEMENT = HERE / "train_supplement_a.jsonl"
GLOSSES = HERE / "glosses.json"

MAX_NGRAM_JACCARD = 0.5
MAX_GLOSS_BIGRAM = 0.4
MAX_GLOSS_SUBSTRING = 8
NONE = "none"
LANGUAGES = ("zh", "en", "mixed")
CATEGORY_COUNTS = {
    "negate-only": 40,
    "adversarial": 20,
    "negate-ask": 25,
    "plain-read": 15,
}
LANGUAGE_COUNTS = {
    "negate-only": {"zh": 24, "en": 8, "mixed": 8},
    "adversarial": {"zh": 12, "en": 4, "mixed": 4},
    "negate-ask": {"zh": 15, "en": 5, "mixed": 5},
    "plain-read": {"zh": 9, "en": 3, "mixed": 3},
}


def load_confirm(path=CONFIRM):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def load_other_prompts():
    """Prompts of the existing sets, used only for scores, never printed."""
    selection = json.loads(SELECTION.read_text(encoding="utf-8"))
    sources = {"selection": [task["prompt"] for task in selection["tasks"]]}
    negation = json.loads(NEGATION.read_text(encoding="utf-8"))
    sources["negation"] = [item["prompt"] for item in negation["items"]]
    for label, path in (("train", TRAIN), ("supplement", SUPPLEMENT)):
        rows = [
            json.loads(line)
            for line in Path(path).read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        sources[label] = [row["state"]["request"] for row in rows]
    return sources


def load_read_only_ids():
    selection = json.loads(SELECTION.read_text(encoding="utf-8"))
    return {tool["id"] for tool in selection["tools"] if tool["effect"] == "read"}


def load_glosses():
    return json.loads(GLOSSES.read_text(encoding="utf-8"))["glosses"]


def check_structure(items, read_only_ids):
    failures = []
    ids = [item.get("id") for item in items]
    if len(ids) != len(set(ids)):
        failures.append(("ids", "id 不唯一"))
    by_category = {}
    by_language = {}
    for item in items:
        category = item.get("category")
        language = item.get("language")
        by_category[category] = by_category.get(category, 0) + 1
        by_language.setdefault(category, {})
        by_language[category][language] = by_language[category].get(language, 0) + 1
    if by_category != CATEGORY_COUNTS:
        failures.append(("counts", f"类别数量 {by_category}"))
    for category, expected in LANGUAGE_COUNTS.items():
        if by_language.get(category) != expected:
            failures.append(
                (f"languages:{category}", f"语言比例 {by_language.get(category)}")
            )
        for language in by_language.get(category, {}):
            if language not in LANGUAGES:
                failures.append((f"languages:{category}", f"未知语言 {language}"))
    for item in items:
        expected = item.get("expected")
        if expected != NONE and expected not in read_only_ids:
            failures.append((item.get("id"), f"expected 不是只读工具: {expected}"))
    return failures


def check_items(items, sources, glosses):
    failures = []
    for item in items:
        best_source, best_score = None, 0.0
        for label, prompts in sources.items():
            score = max_ngram_jaccard(item["prompt"], prompts)
            if score > best_score:
                best_source, best_score = label, score
        if best_score >= MAX_NGRAM_JACCARD:
            failures.append(
                (item["id"], f"5-gram Jaccard {best_score:.3f} 对 {best_source}")
            )
        expected = item.get("expected")
        if expected == NONE:
            continue
        gloss = glosses.get(expected, "")
        if not gloss:
            failures.append((item["id"], f"缺少 {expected} 的 gloss"))
            continue
        bigram = bigram_jaccard(item["prompt"], gloss)
        span = longest_common_substring(item["prompt"], gloss)
        if bigram >= MAX_GLOSS_BIGRAM or span >= MAX_GLOSS_SUBSTRING:
            failures.append(
                (item["id"], f"gloss 相似 bigram={bigram:.3f} lcs={span}")
            )
    return failures


def main():
    items = load_confirm()["items"]
    failures = check_structure(items, load_read_only_ids())
    failures += check_items(items, load_other_prompts(), load_glosses())
    if failures:
        print(f"FAIL {len(failures)}")
        for name, detail in failures:
            print(f"  {name}: {detail}")
        return 1
    print(f"PASS {len(items)} items")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
