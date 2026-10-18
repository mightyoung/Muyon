# Desktop OpenCV version-swap diagnostic

Run from the experiment directory:

```sh
bash checks/native-parity-desktop/setup.sh
bash checks/native-parity-desktop/run.sh
```

`run.sh` uses the already provisioned host Python with `PYTHONPATH=/workspace/ocr-python` for ONNX Runtime **1.21.1**, CPU, two intra-op threads. Override `PARITY_HOST_PYTHON`, `PARITY_HOST_PACKAGES`, `PARITY_OLD_PYTHON`, `PARITY_NEW_PYTHON`, `PARITY_WORK` and `OCR_ASSETS` as needed. Host dependencies are the experiment's existing `checks/requirements.txt`. No Gradle builds, source/vendor edits, model conversion or model downloads are performed. The actual frozen lock is `models.lock.json` at the experiment root; `/workspace/ocr-assets/models.lock.json` does not exist.

Both OpenCV workers use Python **3.9.25**, NumPy **1.26.4**, Pillow **11.3.0**, PyYAML **6.0.3**, pyclipper **1.3.0.post6**, Shapely **2.0.7**. Their only package difference is `opencv-python-headless` **4.5.3.56** versus **4.12.0.88**. The 4.12 wheel declares NumPy>=2 for Python>=3.9; its dependency metadata is explicitly overridden to keep the arithmetic environment identical. Imports and the full numerical run exercise whether this works; this is not a production dependency recommendation. ORT1.21.1 does not provide Python3.9 wheels, so unmodified NPY files bridge preprocessing/inference/postprocessing phases to the shared host runtime. Both sides use the exact same ORT host, not an older ORT substitute.

The harness calls the existing real `cpu_reference.py` detection normalization, DB postprocessing, perspective crop, recognition normalization and CTC decode. Images are generated once using the existing reference and frozen as BGR NPY files; both bindings consume identical bytes. It executes tiny default and small comparison, each with English, Chinese, color, blank and rotated images. Every locked model/config/README is verified by byte size and SHA256. Per-case outputs include actual text, boxes, recognition confidence and hashes/shapes/finite checks/exactness/max absolute/mean absolute/changed element counts for detection input/output, crop pixels, and each recognition input/output. The gate requires exact text/boxes, confidence absolute delta<=1e-5 and tensor allclose(atol=1e-5, rtol=1e-5); it does not declare bitwise parity on an allclose pass.

The report is `evidence/parity-desktop.json`; raw per-stage NPY tensors remain under `/tmp/ocr-native-parity` by default, with reproducible SHA256s in the report. They are runtime artifacts, not checked-in model assets. Re-running regenerates them.

**Android inference: NOT_RUN.** These desktop cv2 binaries are neither Quickbird's Android 4.5.3 binary nor `org.opencv:opencv:4.12.0`. The existing Python reference also differs from Kotlin's `PolygonUnclip`/normalization and does not execute Android Bitmap conversion, JNI, ART, Android ABI packaging or Android ORT. A passing desktop comparison is supporting evidence of version sensitivity only.

For actual Android numerical parity, run two isolated instrumented APK variants on the same ARM64 Android device/emulator: one resolves the frozen Quickbird4.5.3 AAR and the other official4.12.0, while keeping the pinned Kotlin pipeline, ORT1.21.1, models/dictionaries, pixels, threads and configs identical. Verify runtime `Core.VERSION` and the loaded native library path, run real det+rec (not mocks), collect preprocessed tensors, det maps, quads, crops, rec logits, CTC text/confidence and ensure all tensor/OrtSession/Mat resources close. Compare the artifacts with the same explicit tolerances and report each ABI/provider separately. This environment has no usable Android/ART target, so no such outcome is claimed.
