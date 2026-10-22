#!/usr/bin/env python3
"""Content gate: adb exit zero alone never establishes Android test success."""
import argparse
import json
import re
from pathlib import Path


def evaluate(raw: str, adb_exit: int, required: set[str]) -> dict:
    current = {}
    passed = []
    failures = []
    declared = set()
    for line in raw.splitlines():
        if line.startswith("INSTRUMENTATION_STATUS: "):
            key, _, value = line[len("INSTRUMENTATION_STATUS: "):].partition("=")
            if key in {"class", "test"}:
                current[key] = value
            if key == "numtests":
                declared.add(value)
        elif line.startswith("INSTRUMENTATION_STATUS_CODE: "):
            code = line.split(": ", 1)[1]
            identity = current.get("class", "") + "#" + current.get("test", "")
            if code == "0":
                passed.append(identity)
            elif code != "1":
                failures.append({"test": identity, "code": code})
            current = {}
    count = len(passed)
    positive = bool(re.search(rf"^OK \({count} tests?\)\s*$", raw, re.M))
    negative = bool(re.search(r"FAILURES!!!|INSTRUMENTATION_FAILED|Process crashed|shortMsg=|FAILURE:", raw))
    missing = sorted(required - set(passed))
    accepted = (adb_exit == 0 and count > 0 and positive and not negative and not failures
                and declared == {str(count)} and len(set(passed)) == count and not missing)
    return {"gate": "PASS" if accepted else "FAIL", "adb_exit": adb_exit,
            "passed": passed, "missing": missing, "failed_or_skipped": failures,
            "positive_summary": positive, "negative_summary": negative,
            "declared_counts": sorted(declared)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--adb-exit", type=int, required=True)
    parser.add_argument("--required", action="append", required=True)
    args = parser.parse_args()
    result = evaluate(args.log.read_text(), args.adb_exit, set(args.required))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result["gate"] == "PASS" else 1)
