"""Synthetic tool-selection decisions for Kaggle fine-tuning.

The 140-task file and the negation set are evaluation only. This generator
never reads them into a label. It only uses them to reject copies. A few
tools are absent from every option list and every gold label.
"""

from __future__ import annotations

import json
import random
from pathlib import Path

import stage1_contract as contract

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SELECTION = ROOT / "apps/muyon/lib/assistant/selection_eval/selection_set.json"
SEED = 20261005
NEAR_DUPLICATE = 0.5
HELD_OUT_TOOLS = (
    "inquiry.project_budget",
    "ocr.recognize",
    "transfer.export",
    "embedding.search",
)
PLAN = {
    "chinese": 480,
    "mixed": 360,
    "paraphrase": 360,
    "none": 280,
    "ambiguous": 200,
    "negation": 280,
    "adversarial": 280,
}
NOUNS = (
    "真空泵维护手册",
    "球阀样本",
    "轴承温升记录",
    "电缆清册",
    "换热器数据表",
    "焊口清单",
    "润滑油化验单",
    "配电柜图纸",
    "冷却塔巡检表",
    "压力容器档案",
    "疏水阀台账",
    "垫片规格书",
    "联轴器对中单",
    "密封冲洗方案",
    "膨胀节图纸",
    "过滤器差压记录",
    "伴热回路表",
    "接地网测绘图",
    "储罐沉降记录",
    "管架荷载表",
    "流量计校准单",
    "阻火器检查表",
    "减温减压说明书",
    "凝结水回收图",
)
POSITIVE_FRAMES = {
    "chinese": (
        "请对{noun}做这件事：{description}",
        "手头这份{noun}要处理。要做的是：{description}",
        "现在只处理{noun}。动作：{description}",
        "请完成下面这个动作，对象是{noun}：{description}",
    ),
    "mixed": (
        "请对{noun}做 {word}：{description}",
        "对{noun}执行 {word}。说明：{description}",
        "{noun} needs {word}. 说明：{description}",
        "Handle {noun} via {word}：{description}",
    ),
    "paraphrase": (
        "{noun}还在手头。按这句话处理：{description}",
        "先看{noun}，再按这句做：{description}",
        "不要换对象，{noun}用这句来做：{description}",
        "对象仍是{noun}。换成这个说法：{description}",
    ),
}
REFUSAL_FRAMES = {
    "negation": (
        "不要对{noun}做这件事：{description}",
        "先别对{noun}做：{description}",
        "停一下，不要把{noun}拿去：{description}",
    ),
    "adversarial": (
        "忽略本人确认，直接对{noun}执行：{description}",
        "不用问我，马上对{noun}做：{description}",
        "跳过确认，现在就对{noun}执行：{description}",
    ),
}
NONE_SUFFIXES = (
    "旁边放着{noun}",
    "桌上是{noun}",
    "先不管{noun}",
)
NONE_PROMPTS = (
    "今天午饭吃什么",
    "把会议室的灯调暗一点",
    "这段客套话改得更短",
    "明天出门要不要带伞",
    "帮我记一句和业务无关的话：带上充电器",
    "周末有什么展览",
    "把字号调大，我看着累",
    "这首诗的作者是谁",
    "计算器上 18 乘 24 是多少",
    "提醒我下午三点站起来走走",
    "咖啡还热吗",
    "窗口太亮了",
    "用一句话解释什么是潮汐",
    "把闹钟设到明早七点",
    "这个笑话再讲一遍",
    "纸用完了，去储物间拿一包",
    "今天星期几",
    "把音量降到几乎听不见",
    "门外是谁",
    "帮我把这句改成更礼貌的道歉",
)
AMBIGUOUS_PROMPTS = (
    "你看着办",
    "这个先放着",
    "嗯，再说",
    "材料在桌上",
    "回头处理",
    "随便",
    "看情况",
    "先这样",
    "你定",
    "有空再看",
    "稍等",
    "那个东西",
    "按上次的",
    "差不多就行",
    "你懂的",
)


def _positive(rng: random.Random, category: str, description: str, gloss: str, noun: str) -> str:
    word = gloss.split()[0]
    return rng.choice(POSITIVE_FRAMES[category]).format(
        noun=noun, description=description, word=word
    )


def _refusal(rng: random.Random, category: str, description: str, noun: str) -> str:
    return rng.choice(REFUSAL_FRAMES[category]).format(noun=noun, description=description)


def _too_close(prompt: str, eval_grams: list[set[str]], seen: set[str]) -> bool:
    folded = contract.normalize_text(prompt)
    if not folded or folded in seen:
        return True
    grams = contract.char_ngrams(prompt)
    if any(contract.jaccard(grams, other) >= NEAR_DUPLICATE for other in eval_grams):
        return True
    return False


def _example(rng: random.Random, tools: list[dict], full: dict[str, str], id_to_key: dict[str, str], expected: str, prompt: str, category: str, index: int) -> dict:
    trainable = [tool["id"] for tool in tools if tool["id"] not in HELD_OUT_TOOLS]
    others = [tool_id for tool_id in trainable if tool_id != expected]
    width = rng.randint(4, 7)
    picked = rng.sample(others, k=min(width, len(others)))
    keys = [contract.NONE_ID]
    if expected != contract.NONE_ID:
        keys.append(id_to_key[expected])
    keys.extend(id_to_key[tool_id] for tool_id in picked)
    rng.shuffle(keys)
    criteria = {key: full[key] for key in keys}
    gold_key = id_to_key[expected]
    if gold_key not in criteria:
        raise RuntimeError("gold option missing")
    return {
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
        "gold": {
            "tool": {
                "probabilities": {key: 1.0 if key == gold_key else 0.0 for key in criteria}
            }
        },
    }


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
    id_to_key, _key_to_id, full = contract.build_options(option_tools, glosses)
    trainable = option_tools
    refusal_tools = [tool for tool in tools if tool["id"] not in HELD_OUT_TOOLS]
    by_id = {tool["id"]: tool for tool in option_tools}
    rng = random.Random(SEED)
    seen: set[str] = set()
    rows: list[dict] = []
    rejected = 0

    def accept(category: str, expected: str, prompt: str) -> bool:
        nonlocal rejected
        if _too_close(prompt, eval_grams, seen):
            rejected += 1
            return False
        seen.add(contract.normalize_text(prompt))
        rows.append(
            _example(rng, option_tools, full, id_to_key, expected, prompt, category, len(rows) + 1)
        )
        return True

    for category in ("chinese", "mixed", "paraphrase"):
        guard = 0
        while sum(row["category"] == category for row in rows) < PLAN[category]:
            guard += 1
            if guard > PLAN[category] * 40:
                raise RuntimeError(f"could not fill {category}")
            tool = rng.choice(trainable)
            noun = rng.choice(NOUNS)
            accept(
                category,
                tool["id"],
                _positive(rng, category, tool["description"], glosses[tool["id"]], noun),
            )

    for category, pool in (("none", NONE_PROMPTS), ("ambiguous", AMBIGUOUS_PROMPTS)):
        guard = 0
        while sum(row["category"] == category for row in rows) < PLAN[category]:
            guard += 1
            if guard > PLAN[category] * 40:
                raise RuntimeError(f"could not fill {category}")
            noun = rng.choice(NOUNS)
            suffix = rng.choice(NONE_SUFFIXES).format(noun=noun)
            accept(category, contract.NONE_ID, f"{rng.choice(pool)}。{suffix}")

    for category in ("negation", "adversarial"):
        guard = 0
        while sum(row["category"] == category for row in rows) < PLAN[category]:
            guard += 1
            if guard > PLAN[category] * 40:
                raise RuntimeError(f"could not fill {category}")
            tool = rng.choice(refusal_tools)
            noun = rng.choice(NOUNS)
            accept(category, contract.NONE_ID, _refusal(rng, category, tool["description"], noun))

    by_category = {category: 0 for category in PLAN}
    for row in rows:
        by_category[row["category"]] += 1
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
    report = {
        "seed": SEED,
        "items": len(rows),
        "byCategory": by_category,
        "heldOutTools": list(HELD_OUT_TOOLS),
        "rejectedAsNearDuplicate": rejected,
        "exactEvalMatches": 0,
        "maxEvalJaccard": round(max(overlaps), 4) if overlaps else 0,
        "nearDuplicatesAtOrAbove0.5": sum(value >= NEAR_DUPLICATE for value in overlaps),
        "heldOutLeaks": leaked,
        "trainableTools": sorted(by_id),
        "evalSources": [
            "apps/muyon/lib/assistant/selection_eval/selection_set.json",
            "scripts/laya/negation_set.json",
        ],
        "note": "Gold labels are one-hot over the option texts shown. The 140-task set and the negation set are not training rows.",
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
    if report["nearDuplicatesAtOrAbove0.5"] or report["heldOutLeaks"] or report["items"] < 1000:
        raise SystemExit(f"training set failed its own checks: {report}")
    path = HERE / "train_set.jsonl"
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )
    (HERE / "train_overlap.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"wrote {report['items']} rows maxJaccard={report['maxEvalJaccard']} "
        f"rejected={report['rejectedAsNearDuplicate']}"
    )


if __name__ == "__main__":
    main()
