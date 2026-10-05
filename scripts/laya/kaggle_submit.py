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

HERE = Path(__file__).resolve().parent
ENV_FILE = Path("/Users/muyi/Downloads/dev/muspace/.env")
METRICS = Path.home() / ".cache/muyon-eval/stage1-metrics.json"
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


def require_gate(path: Path) -> None:
    if not path.is_file():
        raise SystemExit("stage1 metrics missing; not starting Kaggle")
    payload = json.loads(path.read_text(encoding="utf-8"))
    gate = payload.get("gate1")
    if gate != "pass":
        raise SystemExit(f"GATE1 {gate}; not starting Kaggle")


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


def _write_dataset(folder: Path, user: str) -> None:
    folder.mkdir(parents=True)
    shutil.copyfile(HERE / "train_set.jsonl", folder / "train_set.jsonl")
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


def _dataset_ready(token: str, ref: str) -> None:
    deadline = time.time() + 20 * 60
    while True:
        result = run_scrubbed([KAGGLE, "datasets", "status", ref], token)
        status = scrub(result.stdout).strip().lower()
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


def submit(metrics: Path = METRICS, env_file: Path = ENV_FILE) -> int:
    require_gate(metrics)
    token = read_token(env_file)
    user = username_from_token(token)
    print(f"kaggle user: {user}", flush=True)
    root = Path(f"/tmp/muyon-laya-submit-{os.getpid()}")
    if root.exists():
        shutil.rmtree(root)
    dataset = root / "dataset"
    kernel = root / "kernel"
    try:
        _write_dataset(dataset, user)
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
