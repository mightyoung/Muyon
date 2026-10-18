#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
work=${PARITY_WORK:-/tmp/ocr-native-parity}
old_python=${PARITY_OLD_PYTHON:-/tmp/ocr-parity-old/bin/python}
new_python=${PARITY_NEW_PYTHON:-/tmp/ocr-parity-new/bin/python}
host_python=${PARITY_HOST_PYTHON:-python}
host_packages=${PARITY_HOST_PACKAGES:-/workspace/ocr-python}
assets=${OCR_ASSETS:-/workspace/ocr-assets}
mkdir -p "$work"
PYTHONPATH="$host_packages" "$host_python" "$here/run.py" fixtures --work "$work/fixtures" --assets "$assets"
for version in 4.5.3 4.12.0; do
  cv_python=$old_python
  if [ "$version" = 4.12.0 ]; then cv_python=$new_python; fi
  "$cv_python" -c "import cv2,numpy; assert cv2.__version__ == '$version'; assert numpy.__version__ == '1.26.4'"
  for phase in det-input infer-det post-det infer-rec decode; do
    case "$phase" in
      infer-*) PYTHONPATH="$host_packages" "$host_python" "$here/run.py" "$phase" --work "$work/$version" --assets "$assets" ;;
      *) "$cv_python" "$here/run.py" "$phase" --work "$work/$version" --assets "$assets" ;;
    esac
  done
done
PYTHONPATH="$host_packages" "$host_python" "$here/run.py" compare --work "$work" --assets "$assets" --out "$here/../../evidence/parity-desktop.json"
