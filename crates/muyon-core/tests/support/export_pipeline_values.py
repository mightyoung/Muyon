#!/usr/bin/env python3
"""Export synthetic test vectors, never a production codec or authorization API.
JSON is the sole source. TSV uses UTF-8 hex for every nullable/value string so
JVM checks need no JSON dependency and cannot lose blanks, NUL or emoji bytes.
"""
import argparse
import json
from pathlib import Path
import re

DESCRIPTOR = {"model_version", "tokenizer_version", "dimensions", "chunk_version"}
ROOT = {"contract_major", "schema_major", "synthetic", "descriptor",
        "legacy_paper_only_publicly_resolvable", "fixture_revision",
        "candidate_semantics", "kotlin_api_frozen", "trusted_resolution_implemented",
        "rust_whitespace_reference", "rust_whitespace_code_points",
        "compatibility_cases", "reference_candidate_cases"}
D_FLAGS = ["expected_rust_compatible", "jvm_dimensions_supported"]
C_FLAGS = ["expected_document_id_valid", "expected_result_id_valid",
           "expected_descriptor_valid_rust", "jvm_dimensions_supported",
           "expected_rust_shape_candidate", "expected_jvm_shape_candidate"]

def require(value, message):
    if not value:
        raise ValueError(message)

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result

def load(text):
    return json.loads(text, object_pairs_hook=unique_object)

def keys(value, expected):
    require(type(value) is dict and set(value) == expected, "missing/unknown fixture fields")

def hex_string(value):
    require(type(value) is str, "fixture string required")
    return value.encode("utf-8", errors="strict").hex()

def nullable_string(value):
    return "-" if value is None else hex_string(value)

def descriptor(value):
    keys(value, DESCRIPTOR)
    dimensions = value["dimensions"]
    require(type(dimensions) is int and 0 <= dimensions <= 4294967295, "u32 dimensions required")
    return [hex_string(value["model_version"]), hex_string(value["tokenizer_version"]),
            str(dimensions), hex_string(value["chunk_version"])]

def flag(value):
    require(type(value) is bool, "fixture boolean required")
    return "true" if value else "false"

def export(value):
    keys(value, ROOT)
    for key, expected in [("contract_major", 1), ("schema_major", 1), ("fixture_revision", 2)]:
        require(type(value[key]) is int and value[key] == expected, "unsupported fixture version")
    require(value["synthetic"] is True, "synthetic fixture required")
    require(value["kotlin_api_frozen"] is False and value["trusted_resolution_implemented"] is False,
            "this fixture cannot claim frozen Kotlin APIs or trusted resolution")
    require(value["candidate_semantics"] == "shape_only_not_trusted_resolution", "shape-only semantics required")
    require(value["legacy_paper_only_publicly_resolvable"] is False, "legacy public resolution unavailable")
    require(value["rust_whitespace_reference"] == "Rust 1.93.1 char::is_whitespace / str::trim", "wrong reference")
    compatibility = value["compatibility_cases"]
    candidates = value["reference_candidate_cases"]
    points = value["rust_whitespace_code_points"]
    require(type(compatibility) is list and type(candidates) is list and type(points) is list,
            "fixture lists required")
    require(all(type(cp) is int and 0 <= cp <= 0x10ffff and not 0xd800 <= cp <= 0xdfff for cp in points),
            "Unicode scalar code points required")
    require(points == sorted(set(points)), "sorted unique code points required")
    rows = [["H", "muyon.public-pipeline-values", "1", "1", "2", "true", "false", "false",
             "shape_only_not_trusted_resolution", str(len(compatibility)), str(len(candidates)), str(len(points))],
            ["B"] + descriptor(value["descriptor"])]
    rows += [["W", str(cp)] for cp in points]
    seen = set()
    for tag, cases, fields in [("D", compatibility, {"id", "index", "query", *D_FLAGS}),
                               ("C", candidates, {"id", "document_id", "result_id", "model", *C_FLAGS})]:
        for case in cases:
            keys(case, fields)
            name = case["id"]
            require(type(name) is str and re.fullmatch(r"[A-Za-z0-9_+.:-]+", name) is not None
                    and name not in seen, "nonempty unique ASCII case ID required")
            seen.add(name)
            if tag == "D":
                row = [tag, name] + descriptor(case["index"]) + descriptor(case["query"])
                row += [flag(case[key]) for key in D_FLAGS]
            else:
                model = ["-"] * 4 if case["model"] is None else descriptor(case["model"])
                row = [tag, name, nullable_string(case["document_id"]), nullable_string(case["result_id"])] + model
                row += [flag(case[key]) for key in C_FLAGS]
            rows.append(row)
    return "".join("\t".join(row) + "\n" for row in rows)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1] / "fixtures/public_pipeline.json")
    args = parser.parse_args()
    print(export(load(args.fixture.read_text(encoding="utf-8"))), end="")
