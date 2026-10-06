"""Rejection tests for check_confirm_set.py. Standard library only, no model."""

import unittest

import check_confirm_set as check


def make_item(item_id, category, language, prompt, expected):
    return {
        "id": item_id,
        "category": category,
        "language": language,
        "prompt": prompt,
        "expected": expected,
    }


def full_items():
    """A structurally valid synthetic set: exact counts and language mix."""
    items = []
    index = 0
    for category, languages in check.LANGUAGE_COUNTS.items():
        for language, count in languages.items():
            for _ in range(count):
                index += 1
                expected = (
                    "none"
                    if category in ("negate-only", "adversarial")
                    else "inquiry.search"
                )
                items.append(
                    make_item(
                        f"x-{index:03d}",
                        category,
                        language,
                        f"合成请求 {index}",
                        expected,
                    )
                )
    return items


class StructureChecks(unittest.TestCase):
    def test_valid_structure_passes(self):
        self.assertEqual(check.check_structure(full_items(), {"inquiry.search"}), [])

    def test_duplicate_ids_rejected(self):
        items = full_items()
        items[1]["id"] = items[0]["id"]
        failures = check.check_structure(items, {"inquiry.search"})
        self.assertTrue(any(name == "ids" for name, _ in failures))

    def test_wrong_category_counts_rejected(self):
        failures = check.check_structure([make_item("a", "plain-read", "zh", "x", "none")], {"inquiry.search"})
        self.assertTrue(any(name == "counts" for name, _ in failures))

    def test_wrong_language_mix_rejected(self):
        items = full_items()
        # Flip one negate-only item from zh to en: the exact mix no longer holds.
        for item in items:
            if item["category"] == "negate-only" and item["language"] == "zh":
                item["language"] = "en"
                break
        failures = check.check_structure(items, {"inquiry.search"})
        self.assertTrue(any(name == "languages:negate-only" for name, _ in failures))

    def test_unknown_language_rejected(self):
        items = full_items()
        items[0]["language"] = "de"
        failures = check.check_structure(items, {"inquiry.search"})
        self.assertTrue(any(name.startswith("languages") for name, _ in failures))

    def test_non_read_expected_rejected(self):
        items = full_items()
        items[0]["expected"] = "knowledge.delete"
        failures = check.check_structure(items, {"inquiry.search"})
        self.assertTrue(any("expected" in detail for _, detail in failures))


class ItemChecks(unittest.TestCase):
    def test_valid_items_pass(self):
        self.assertEqual(
            check.check_items(
                full_items(),
                {"selection": []},
                {"inquiry.search": "find a material"},
            ),
            [],
        )

    def test_near_duplicate_of_existing_prompt_rejected(self):
        prompt = "帮我找一下离心泵这个物料。"
        failures = check.check_items(
            [make_item("a", "plain-read", "zh", prompt, "inquiry.search")],
            {"selection": [prompt]},
            {"inquiry.search": "find a material"},
        )
        self.assertTrue(any("5-gram Jaccard" in detail for _, detail in failures))

    def test_gloss_bigram_overlap_rejected(self):
        # Bigram Jaccard 0.727 but the longest common span is only 7.
        failures = check.check_items(
            [make_item("a", "plain-read", "en", "abcdefgXhij", "inquiry.search")],
            {"selection": []},
            {"inquiry.search": "abcdefghij"},
        )
        self.assertTrue(
            any("bigram=" in detail and "lcs=7" in detail for _, detail in failures)
        )

    def test_gloss_common_span_rejected(self):
        # Longest common span 9 while bigram Jaccard stays below 0.4.
        failures = check.check_items(
            [make_item("a", "plain-read", "en", "mnopqrstu", "inquiry.search")],
            {"selection": []},
            {"inquiry.search": "abcdefghijklmnopqrstuvwxyz"},
        )
        self.assertTrue(
            any("bigram=" in detail and "lcs=9" in detail for _, detail in failures)
        )


if __name__ == "__main__":
    unittest.main()
