#!/usr/bin/env python3
"""Provision fixed CI assets separately from offline verification; never infer licensing."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import urllib.parse
import urllib.request
from model_package_gate import REVIEWED_PROVENANCE_NOTICE

SPEC = importlib.util.spec_from_file_location("prepare_models", Path(__file__).parents[1] / "prepare-model-assets.py")
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


def download(url, path, size=None, digest=None):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("CI model source must be credential-free HTTPS")
    if path.exists():
        if size is not None and digest and path.is_file() and path.stat().st_size == size:
            with path.open("rb") as existing:
                if hashlib.file_digest(existing, "sha256").hexdigest() == digest:
                    return
        raise ValueError("Existing model input differs; preserve it and use a separate task-owned source directory")
    # No archive extraction or executable input. Only named, bounded data files.
    limit = size if size is not None else 131072
    path.parent.mkdir(parents=True, exist_ok=True)
    part = path.with_suffix(path.suffix + ".part")
    try:
        with urllib.request.urlopen(url, timeout=60) as response, part.open("wb") as output:
            if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                raise ValueError("CI asset redirect must remain HTTPS")
            total = 0
            hasher = hashlib.sha256()
            while True:
                block = response.read(min(1048576, limit + 1 - total))
                if not block:
                    break
                total += len(block)
                if total > limit:
                    raise ValueError("CI asset exceeds fixed bound")
                hasher.update(block)
                output.write(block)
        if not total or (size is not None and total != size) or (digest and hasher.hexdigest() != digest):
            raise ValueError("CI asset size/hash mismatch")
        os.replace(part, path)
    finally:
        part.unlink(missing_ok=True)


def default_provenance():
    lines = [
        "Fixed official-model artifact provenance for Muyon Android",
        "",
        "Embedding GGUF is published by ggml-org; its pinned model card declares",
        "google/embeddinggemma-2 as base and Apache-2.0. The GGUF card says automatic",
        "ggml-org/convert conversion but does not pin the actual converter or base revision.",
        "Google model card 914f7f89142e33e77833254d9c9b90c3cef7303b separately records",
        "the base-model license declaration. Do not infer the GGUF conversion used that revision.",
        "Google license reference: https://ai.google.dev/gemma/apache_2",
        "PaddlePaddle pinned detector and recognizer model cards declare Apache-2.0.",
        "Full pinned cards and the Apache standard license text accompany this record.",
        "",
    ]
    for name, (relative, size, digest) in PREPARE.MODELS.items():
        lines.extend([f"{name}: {size} bytes; SHA256 {digest}", PREPARE.OFFICIAL_SOURCES[name], ""])
    for name, (url, digest) in PREPARE.NOTICES.items():
        lines.extend([f"{name}: SHA256 {digest}", url, ""])
    lines.extend([
        "The earlier user-supplied local GGUF (SHA256 6f1bd4ac6c5df7444f9cca7ca36cafe6cfa34cd6f49fefb1e0b4be8143aed8bc)",
        "is a different artifact and remains untouched; its conversion/source provenance was not established.",
        "Artifact hash/source records and retained license texts do not replace downstream distribution review.",
    ])
    return ("\n".join(lines) + "\n").encode()


def prepare(source, assets, fetch=False):
    if fetch:
        for name, (relative, size, digest) in PREPARE.MODELS.items():
            download(PREPARE.OFFICIAL_SOURCES[name], source / relative, size, digest)
    # This text is required provenance input, not an agent's licensing conclusion.
    input_notice = source / "LOCAL_MODELS.txt"
    notice = input_notice.read_bytes() if input_notice.is_file() else default_provenance()
    if not notice.strip() or len(notice) > 131072:
        raise ValueError("Supply reviewed model provenance and licensing notices")
    PREPARE.prepare(source, assets, fetch_notices=fetch)
    # main/assets already owns LOCAL_MODELS.txt. AssetSet rejects a same-name
    # file from another main source directory, even if its bytes are identical.
    legacy = assets / "notices/LOCAL_MODELS.txt"
    if legacy.exists() and legacy.read_bytes() != notice:
        raise ValueError("Conflicting legacy external notice; preserve and review it before migration")
    (assets / "notices" / REVIEWED_PROVENANCE_NOTICE).write_bytes(notice)
    if legacy.exists():
        # Content is preserved under the distinct reviewed-provenance name.
        legacy.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("assets", type=Path)
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args()
    prepare(args.source, args.assets, args.fetch)
