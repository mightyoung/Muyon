#!/usr/bin/env python3
"""Prepare fixed offline assets outside Git; requires PyYAML for proper Unicode YAML."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import yaml

MODELS = {
    "embedding.gguf": ("models/embeddinggemma-2-Q8_0.gguf", 309855456, "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"),
    "det.onnx": (".ocr-validation/models/det.onnx", 4826518, "a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d"),
    "rec.onnx": (".ocr-validation/models/rec.onnx", 16534782, "da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092"),
    "det.yml": (".ocr-validation/models/det.yml", 903, "98069072e1b6b37d727fd9d9f11725faa46d6ea0de012f2ed26caea011c37699"),
    "rec.yml": (".ocr-validation/models/rec.yml", 148345, "5dfeb2777f6d0db8177d8128a8acfcf6e6276dc4ac73ea3bf0dc06d6a5e85d8e"),
}

OFFICIAL_SOURCES = {
    "embedding.gguf": "https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/58faf90940886df2d62be555c8765d00dac362c5/embeddinggemma-2-Q8_0.gguf",
    "det.onnx": "https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx/resolve/e6f4fa85f00e168c862bc462aebca69eef9b3d3d/inference.onnx",
    "rec.onnx": "https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx/resolve/ed152b8b495f84de93cda5709d768548a9127622/inference.onnx",
    "det.yml": "https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx/raw/e6f4fa85f00e168c862bc462aebca69eef9b3d3d/inference.yml",
    "rec.yml": "https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx/raw/ed152b8b495f84de93cda5709d768548a9127622/inference.yml",
}

NOTICES = {
    "llama-MIT.txt": ("https://raw.githubusercontent.com/ggml-org/llama.cpp/a01ce9ffc64cf370439d6f861a534a65100133ae/LICENSE", "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d"),
    "onnxruntime-MIT.txt": ("https://raw.githubusercontent.com/microsoft/onnxruntime/v1.23.0/LICENSE", "2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c"),
    "PaddleOCR-Apache2.txt": ("https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/LICENSE", "3840c5c0c61c294264d2dd77b8777be6ddd90121ef4e0e64abcd22edea581d6e"),
    "Embedding-GGUF-model-card.txt": ("https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/raw/58faf90940886df2d62be555c8765d00dac362c5/README.md", "319bbb434d2abe8f54f8571fa1e90973aa3cde85ab260312b7b7f8e3d9da02f5"),
    "Embedding-base-model-card.txt": ("https://huggingface.co/google/embeddinggemma-2/raw/914f7f89142e33e77833254d9c9b90c3cef7303b/README.md", "b677a0ee2818c36f091b65fd3d9b4baea9f04d53b02b49cae916c74bf9682037"),
    "PaddleOCR-det-model-card.txt": ("https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx/raw/e6f4fa85f00e168c862bc462aebca69eef9b3d3d/README.md", "951c155673ac6c15feb85857c9024a62266e5956d15319ce578a8f508f399d66"),
    "PaddleOCR-rec-model-card.txt": ("https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx/raw/ed152b8b495f84de93cda5709d768548a9127622/README.md", "7331c129fd5024b6a0abd1f510cfdfb2d7714fdcdbb00df21a0cb8b48e6683ee"),
    "Model-Apache-2.0.txt": ("https://www.apache.org/licenses/LICENSE-2.0.txt", "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30"),
}

def prepare(source, output, fetch_notices=False):
    target = output / "local-models"
    target.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for name, (relative, size, digest) in MODELS.items():
        path = source / relative
        with path.open("rb") as model_input:
            actual = hashlib.file_digest(model_input, "sha256").hexdigest()
        if path.stat().st_size != size or actual != digest:
            raise ValueError(f"Fixed model mismatch: {name}")
        shutil.copyfile(path, target / name)
        manifest[name] = {"bytes": size, "sha256": digest}
    config = yaml.safe_load((target / "rec.yml").read_text())
    dictionary = [""] + config["PostProcess"]["character_dict"] + [" "]
    if len(dictionary) != 18385:
        raise ValueError("Unexpected OCR dictionary classes")
    data = json.dumps(dictionary, ensure_ascii=False, separators=(",", ":")).encode()
    (target / "dictionary.json").write_bytes(data)
    manifest["dictionary.json"] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    notices = output / "notices"
    notices.mkdir(exist_ok=True)
    for name, (url, digest) in NOTICES.items():
        path = notices / name
        if not path.is_file() and fetch_notices:
            with urllib.request.urlopen(url, timeout=40) as response:
                value = response.read()
            if hashlib.sha256(value).hexdigest() != digest:
                raise ValueError(f"Upstream notice hash mismatch: {name}")
            path.write_bytes(value)
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Missing/changed notice: {name}; supply fixed text or use --fetch-notices")
    print(f"Prepared {len(manifest)} verified offline assets: {target}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fetch-notices", action="store_true")
    args = parser.parse_args()
    prepare(args.source, args.output, args.fetch_notices)
