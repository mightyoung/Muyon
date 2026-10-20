#!/usr/bin/env python3
"""Aggregate ordered picker runs without omitting any product test method."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from instrumentation_gate import evaluate


def check(manifest, source):
    expected = set()
    for path in source.rglob("*Test.kt"):
        text = path.read_text()
        package = re.search(r"^package ([\w.]+)", text, re.M).group(1)
        name = re.search(r"^class (\w+)", text, re.M).group(1)
        expected.update(f"{package}.{name}#{method}" for method in re.findall(r"@Test\s+fun (\w+)\(", text))
    assert expected, "empty required inventory"
    assert manifest["build_id"].startswith(manifest["source_commit"] + ":"), "source identity differs"
    for key in ("apk", "test_apk"):
        assert hashlib.sha256(Path(manifest[key]).read_bytes()).hexdigest() == manifest[key + "_sha256"], key + " changed"
    actual = []
    runs = []
    for run in manifest["runs"]:
        assert run["build_id"] == manifest["build_id"], "run build identity differs"
        assert run["apk_sha256"] == manifest["apk_sha256"], "run APK identity differs"
        assert run["test_apk_sha256"] == manifest["test_apk_sha256"], "run test APK identity differs"
        assert hashlib.sha256(Path(run["log"]).read_bytes()).hexdigest() == run["log_sha256"], "run log changed"
        result = evaluate(Path(run["log"]).read_text(), run["adb_exit"], set(run["required"]))
        assert result["gate"] == "PASS", result
        assert set(result["passed"]) == set(run["required"]), "unexpected or unlisted selector result"
        actual.extend(result["passed"])
        runs.append({"log": run["log"], "passed": len(result["passed"]), "gate": "PASS"})
    assert set(actual) == expected, {"missing": sorted(expected - set(actual)), "unexpected": sorted(set(actual) - expected)}
    assert len(actual) == len(set(actual)), "duplicate selector results"
    return {"gate": "PASS", "build_id": manifest["build_id"], "required_methods": len(expected), "runs": runs,
            "boundary": "product instrumentation only; I04, production pricing proof and real provider/tool-loop remain separate gates"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    print(json.dumps(check(json.loads(args.manifest.read_text()), args.source), indent=2))
