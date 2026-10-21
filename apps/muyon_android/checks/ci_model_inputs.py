#!/usr/bin/env python3
"""Provision fixed CI assets separately from offline verification; never infer licensing."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import urllib.parse
import urllib.request

SPEC = importlib.util.spec_from_file_location("prepare_models", Path(__file__).parents[1] / "prepare-model-assets.py")
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


def download(url, path, size=None, digest=None):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("CI model source must be credential-free HTTPS")
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


def prepare(source, assets, base_url=None):
    if base_url:
        base = urllib.parse.urlsplit(base_url)
        if base.query or base.fragment:
            raise ValueError("Use a source directory URL without query/fragment")
        for _, (relative, size, digest) in PREPARE.MODELS.items():
            download(base_url.rstrip("/") + "/" + relative, source / relative, size, digest)
        download(base_url.rstrip("/") + "/notices/LOCAL_MODELS.txt", source / "LOCAL_MODELS.txt")
    # This text is required provenance input, not an agent's licensing conclusion.
    notice = (source / "LOCAL_MODELS.txt").read_bytes()
    if not notice.strip() or len(notice) > 131072:
        raise ValueError("Supply reviewed model provenance and licensing notices")
    PREPARE.prepare(source, assets, fetch_notices=bool(base_url))
    (assets / "notices/LOCAL_MODELS.txt").write_bytes(notice)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("assets", type=Path)
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args()
    base = os.environ.get("MUYON_MODEL_INPUT_URL", "") if args.fetch else None
    if args.fetch and not base:
        raise SystemExit("MUYON_MODEL_INPUT_URL is required; fixed embedding source/provenance is not yet provisioned")
    prepare(args.source, args.assets, base)
