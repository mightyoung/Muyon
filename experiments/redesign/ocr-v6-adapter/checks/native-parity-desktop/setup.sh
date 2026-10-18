#!/usr/bin/env bash
set -euo pipefail
# Standard public uv/PyPI dependencies only. All writes remain under /tmp.
export UV_CACHE_DIR=${UV_CACHE_DIR:-/tmp/ocr-parity-uv}
export UV_PYTHON_BIN_DIR=${UV_PYTHON_BIN_DIR:-/tmp/ocr-parity-python-bin}
uv python install 3.9.25 --install-dir /tmp/ocr-parity-python --no-progress
py=/tmp/ocr-parity-python/cpython-3.9-linux-x86_64-gnu/bin/python3.9
for label in old new; do
  uv venv --python "$py" "/tmp/ocr-parity-$label"
  uv pip install --python "/tmp/ocr-parity-$label/bin/python" numpy==1.26.4 Pillow==11.3.0 PyYAML==6.0.3 pyclipper==1.3.0.post6 shapely==2.0.7 --no-progress
done
uv pip install --python /tmp/ocr-parity-old/bin/python opencv-python-headless==4.5.3.56 --no-progress
# Intentional metadata override: old OpenCV cannot import NumPy2. Test imports in run.sh.
uv pip install --python /tmp/ocr-parity-new/bin/python opencv-python-headless==4.12.0.88 --no-deps --no-progress
