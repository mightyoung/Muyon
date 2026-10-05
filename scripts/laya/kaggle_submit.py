"""Upload the private dataset and start the private 2xT4 notebook.

Reads only the Kaggle-apikey line. The value is placed in KAGGLE_API_TOKEN
for the Kaggle subprocess and is removed from anything this process prints.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import stage2_data
import stage2_threshold as gate

HERE = Path(__file__).resolve().parent
ENV_FILE = Path("/Users/muyi/Downloads/dev/muspace/.env")
PYTHON = "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
KAGGLE = "/Library/Frameworks/Python.framework/Versions/3.12/bin/kaggle"
DATASET_SLUG = "muyon-laya-tool-choices"
DATASET_TITLE = "Muyon Laya tool choices"
KERNEL_SLUG = "muyon-laya-tool-finetune"
KERNEL_TITLE = "Muyon Laya tool finetune"
TOKEN_RE = re.compile(r"KGAT_[A-Za-z0-9._\-]+")
USER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{2,}$")


def scrub(text: str) -> str:
    return TOKEN_RE.sub("KGAT_[redacted]", text)


def require_stage2(train_path: Path, overlap_path: Path, selection_path: Path) -> dict:
    """D-R8c starts Stage 2 without treating a failed gate 1b as a pass.

    The check is the training file, the leakage report, and the 67-task
    definition. It does not read stage1b-metrics.json and it does not open .env.
    """
    if not train_path.is_file():
        raise SystemExit("training file missing; not starting Kaggle")
    if not overlap_path.is_file():
        raise SystemExit("overlap report missing; not starting Kaggle")
    if not selection_path.is_file():
        raise SystemExit("selection set missing; not starting Kaggle")
    try:
        rows = gate.load_jsonl(train_path)
        overlap = json.loads(overlap_path.read_text(encoding="utf-8"))
        selection = json.loads(selection_path.read_text(encoding="utf-8"))
        gate.assert_read_only_targets(rows, selection["tools"], set(stage2_data.HELD_OUT_TOOLS))
        gate.assert_overlap(overlap)
        gate.assert_answerable_mix(selection["tasks"], selection["tools"])
        training, validation = gate.validation_split(rows)
        if len(training) < 1000 or not validation:
            raise ValueError(f"upload {len(training)} validation {len(validation)}")
        report = gate.reweight(
            validation,
            gate.target_mix(selection["tasks"], selection["tools"]),
            text_of=lambda row: row["state"]["request"],
            expected_of=lambda row: row["expected"],
        )
    except (OSError, json.JSONDecodeError, KeyError, ValueError) as error:
        raise SystemExit(f"{error}; not starting Kaggle") from None
    report["uploadRows"] = len(training)
    report["validationRows"] = len(validation)
    return report


def read_token(path: Path) -> str:
    found = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if not line.startswith("Kaggle-apikey"):
            continue
        _key, separator, value = line.partition("=")
        if separator != "=":
            continue
        found = value.strip().strip('"').strip("'")
        break
    if not found or not found.startswith("KGAT_") or len(found) < 12:
        raise SystemExit("Kaggle-apikey is missing or is not a KGAT token")
    return found


def run_scrubbed(args: list[str], token: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    for key in ("KAGGLE_USERNAME", "KAGGLE_KEY", "KAGGLE_API_TOKEN"):
        env.pop(key, None)
    env["KAGGLE_API_TOKEN"] = token
    result = subprocess.run(args, env=env, text=True, capture_output=True, check=False)
    sys.stdout.write(scrub(result.stdout))
    sys.stderr.write(scrub(result.stderr))
    return result


def username_from_token(token: str) -> str:
    code = (
        "from kaggle.api.kaggle_api_extended import KaggleApi\n"
        "api = KaggleApi()\n"
        "api.authenticate()\n"
        "print(api.config_values.get('username') or '')\n"
    )
    result = run_scrubbed([PYTHON, "-c", code], token)
    user = scrub(result.stdout).strip().splitlines()[-1] if result.stdout.strip() else ""
    if result.returncode != 0 or not USER_RE.fullmatch(user) or user.startswith("KGAT"):
        raise SystemExit(f"Kaggle rejected the token or returned no username (exit {result.returncode})")
    return user


def upload_rows(train_path: Path) -> list[dict]:
    """The decision-threshold split stays local. Kaggle trains on the rest."""
    _training, _validation = gate.validation_split(gate.load_jsonl(train_path))
    return _training


def _write_dataset(folder: Path, user: str, train_path: Path) -> None:
    folder.mkdir(parents=True)
    lines = [json.dumps(row, ensure_ascii=False) for row in upload_rows(train_path)]
    (folder / "train_set.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
    metadata = {
        "title": DATASET_TITLE,
        "id": f"{user}/{DATASET_SLUG}",
        "licenses": [{"name": "CC0-1.0"}],
    }
    (folder / "dataset-metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )


def _write_kernel(folder: Path, user: str) -> None:
    folder.mkdir(parents=True)
    shutil.copyfile(HERE / "laya_finetune_tool_selection_kaggle.ipynb", folder / "notebook.ipynb")
    metadata = {
        "id": f"{user}/{KERNEL_SLUG}",
        "title": KERNEL_TITLE,
        "code_file": "notebook.ipynb",
        "language": "python",
        "kernel_type": "notebook",
        "is_private": True,
        "enable_gpu": True,
        "enable_internet": True,
        "machine_shape": "NvidiaTeslaT4",
        "dataset_sources": [f"{user}/{DATASET_SLUG}"],
        "competition_sources": [],
        "kernel_sources": [],
        "model_sources": [],
    }
    (folder / "kernel-metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )


def status_line(text: str) -> str:
    """The CLI prints a version warning before the one-word status."""
    lines = []
    for line in scrub(text).splitlines():
        stripped = line.strip().lower()
        if not stripped or stripped.startswith("warning:"):
            continue
        lines.append(stripped)
    return lines[-1] if lines else ""


def _dataset_ready(token: str, ref: str) -> None:
    deadline = time.time() + 20 * 60
    while True:
        result = run_scrubbed([KAGGLE, "datasets", "status", ref], token)
        status = status_line(result.stdout + "\n" + result.stderr)
        print(f"dataset status: {status or 'empty'}", flush=True)
        if result.returncode != 0:
            raise SystemExit(f"dataset status failed ({result.returncode})")
        if status == "ready":
            return
        if status in {"error", "failed", "deleted"}:
            raise SystemExit(f"dataset status {status}")
        if time.time() > deadline:
            raise SystemExit(f"dataset stayed {status}")
        time.sleep(30)


def submit(
    env_file: Path = ENV_FILE,
    train_path: Path = HERE / "train_set.jsonl",
    overlap_path: Path = HERE / "train_overlap.json",
    selection_path: Path = stage2_data.SELECTION,
) -> int:
    report = require_stage2(train_path, overlap_path, selection_path)
    print(
        "stage2 mix "
        f"upload={report['uploadRows']} validation={report['validationRows']} "
        f"target={report['targetCounts']} source={report['sourceCounts']} "
        f"unmatched={report['unmatchedTarget']} dropped={report['droppedSource']}",
        flush=True,
    )
    token = read_token(env_file)
    user = username_from_token(token)
    print(f"kaggle user: {user}", flush=True)
    root = Path(f"/tmp/muyon-laya-submit-{os.getpid()}")
    if root.exists():
        shutil.rmtree(root)
    dataset = root / "dataset"
    kernel = root / "kernel"
    try:
        _write_dataset(dataset, user, train_path)
        created = run_scrubbed(
            [KAGGLE, "datasets", "create", "-p", str(dataset), "--keep-tabular"],
            token,
        )
        combined = scrub(created.stdout + "\n" + created.stderr).lower()
        if "public dataset is being created" in combined:
            raise SystemExit("refusing a public dataset")
        if "private dataset is being created" not in combined:
            if "already in use" not in combined and "already exists" not in combined:
                raise SystemExit(f"dataset create failed ({created.returncode})")
            versioned = run_scrubbed(
                [
                    KAGGLE,
                    "datasets",
                    "version",
                    "-p",
                    str(dataset),
                    "-m",
                    "Synthetic tool-choice rows",
                    "--keep-tabular",
                ],
                token,
            )
            version_text = scrub(versioned.stdout + "\n" + versioned.stderr).lower()
            if "dataset version is being created" not in version_text:
                raise SystemExit(f"dataset version failed ({versioned.returncode})")
        ref = f"{user}/{DATASET_SLUG}"
        _dataset_ready(token, ref)
        _write_kernel(kernel, user)
        pushed = run_scrubbed(
            [KAGGLE, "kernels", "push", "-p", str(kernel), "--accelerator", "NvidiaTeslaT4"],
            token,
        )
        push_text = scrub(pushed.stdout + "\n" + pushed.stderr).lower()
        if "successfully pushed" not in push_text or "kernel push error" in push_text:
            raise SystemExit(f"kernel push failed ({pushed.returncode})")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print(f"private kernel pushed: {user}/{KERNEL_SLUG}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(submit())
    except SystemExit:
        raise
    except Exception as error:
        print(scrub(f"{type(error).__name__}: {error}"), file=sys.stderr)
        raise SystemExit(1) from None
