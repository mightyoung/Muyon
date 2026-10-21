# Product CI and resource remediation

Review baseline: `30c033cd8542f566d40e9248bcc498e7efce7fc6`. This record covers
Important findings 7 and 8; it does not grant release or integration approval.

## Resource inventory and resolution

| Current product resource | Observed source before correction | Resolution |
| --- | --- | --- |
| `res/font/claude_sans.ttf` | Installed Claude `AnthropicSans-Romans-Variable-25x258.ttf`, SHA256 `4eda2c42031a090a3d01cd58ada3de00f467e3e359efad36572f26e43ecba65f` | Removed; platform `FontFamily.SansSerif`. No vendor glyph bytes packaged. |
| `res/font/claude_serif.ttf` | Installed Claude `AnthropicSerif-Romans-Variable-25x258.ttf`, SHA256 `cb2c65e0d0d326181f2a2525ad344cacc850a41c24aeaea51cc70df8c88a3231` | Removed; platform `FontFamily.Serif`. Existing16/24 typography and reply width retained. |
| `res/drawable/wb_add.xml` | WorkBuddy `common-add.svg` | Replaced with independently authored perpendicular lines. |
| `res/drawable/wb_chat.xml` | WorkBuddy `chat-bubble.svg` | Replaced with independently authored message polygon and text rule. |
| `res/drawable/wb_document.xml` | WorkBuddy `file-text.svg` | Replaced with independently authored rectangular page and rules. |
| `res/drawable/wb_menu.xml` | WorkBuddy `cloud-conversation-menu.svg` | Replaced with independently authored three horizontal lines. |
| `res/drawable/wb_send.xml` | WorkBuddy `Button-send.svg` | Replaced with independently authored upright arrow. |
| `res/drawable/muyon_avatar.png` | New image-tool generation documented in reference evidence, SHA256 `d117edae10e75d44f7542107711e1291d73da1ddd71e0cf1b0785eb511dca8bb` | Retained; the recorded provenance does not identify an extracted vendor image. |

The audit found no recorded redistribution permission for the extracted fonts
and icons. This is a missing permission basis, not a legal finding. Access to the
reference bundles was not treated as a license. Old commits, screenshots and
already-built APKs still describe/contain the earlier resources; removing current
source files does not retroactively clear those artifacts for public distribution.
The legacy Kotlin names `ClaudeSansFont` and `ClaudeReplyFont`, and `wb_*` resource
IDs, remain source-compatible identifiers; their bytes now come from the platform
or original geometry. No icon/font dependency was added.

Muse-inspired layout, spacing, color and button shapes remain native Compose
code. The implementation does not embed the private reference applications or
claim access to their backends. The model/runtime license inventory is separate:
llama.cpp MIT, ONNX Runtime MIT and PaddleOCR Apache2 notices are hash-checked;
the earlier user-supplied GGUF's converter/source provenance was not established.
The current candidate instead pins a separately published ggml-org artifact and
retains its model card, the Google base-model card and standard Apache-2.0 text.
Their declarations provide the recorded licensing basis; the exact conversion
revision remains unspecified. Runtime notices alone do not establish model weight
redistribution rights, and product release approval remains a separate decision.

## New product CI contract

`.github/workflows/muyon-product.yml` applies to the real `crates/` workspace and
`apps/muyon_android/`, including their three path-linked laboratory core
dependencies. It runs on the integration branch push, affected pull requests to
`develop`, changes on `develop`, and manual dispatch. It checks out the exact PR
head, records its SHA and uses read-only repository permissions.

Required producers:

1. Locked Cargo dependency provisioning followed by offline production workspace
   tests, strict Clippy and Python checker tests. Tests use local fixtures and
   do not call paid model/search providers.
2. Actual arm64/x86 Android product and embedding library build, current UniFFI
   bridge regeneration/byte comparison, actual app/test-APK compilation and lint.
   After Maven provisioning, a clean offline build must succeed. Product and
   model package gates verify both ABIs, native16KiB alignment, fixed weight
   hashes, dictionary and notices. Instrumentation is compiled, not executed by
   this workflow; the recorded API26 device suite remains a separate gate.
3. An always-running aggregate requires both producers to succeed. There is no
   `continue-on-error`, missing-input skip or substituted model success. Failed
   jobs retain source/build/check logs. APKs/model files are not uploaded by this
   workflow while redistribution prerequisites remain unresolved.

Build scripts and the APK checker now select Linux/macOS NDK host tools instead
of hard-coding the macOS toolchain path. Existing NDK28.2.13676358, CMake3.22.1,
AGP8.11.1 and Kotlin2.2.20 pins remain. Gradle8.13 uses the existing repository's
official distribution SHA256 pin. This workflow does not enable branch protection
or authorize replacing/merging the held integration dependencies.

## Fixed official model provisioning, without repository URL configuration

The original CI proposal required `MUYON_MODEL_INPUT_URL` because the user-supplied
local GGUF lacked an established converter/source. That configuration requirement
has been removed. Following user authorization to reuse local files or download
official files, the current candidate pins a different, published artifact:

- `ggml-org/embeddinggemma-2-GGUF`, revision
  `58faf90940886df2d62be555c8765d00dac362c5`, file
  `embeddinggemma-2-Q8_0.gguf`, **309855456 bytes**, SHA256
  `2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135`.
- The pinned GGUF model card declares `google/embeddinggemma-2`, Apache-2.0 and
  automatic `ggml-org/convert` conversion; it does not identify the exact converter
  or base revision used for conversion. Google model card at
  `914f7f89142e33e77833254d9c9b90c3cef7303b` is separately retained as a license
  reference, without claiming it was the converter's input revision.
- The prior user-supplied file, size309855520 and SHA256 `6f1bd4ac6c5df7444f9cca7ca36cafe6cfa34cd6f49fefb1e0b4be8143aed8bc`,
  is a distinct artifact. It is not overwritten or represented as sharing the new
  source; earlier inference evidence for it does not accept the new artifact.

`prepare-model-assets.py` records exact official URLs, sizes and hashes. The two
PP-OCRv5 files/configurations retain their existing pinned PaddlePaddle revisions
and hashes. `ci_model_inputs.py --fetch` provisions those five named files and
the fixed license/model-card texts. No authentication or repository URL variable
is needed; missing/corrupted downloads fail rather than skip the real gate.

The task-owned input directory contract is:

```text
models/embeddinggemma-2-Q8_0.gguf
.ocr-validation/models/det.onnx
.ocr-validation/models/rec.onnx
.ocr-validation/models/det.yml
.ocr-validation/models/rec.yml
```

The five model/config files must match existing `prepare-model-assets.py` sizes
and SHA256 pins. The Unicode dictionary is regenerated and the Android build
independently checks its fixed digest. Default provenance records all fixed URLs,
sizes/hashes and licensing declarations. An optional input `LOCAL_MODELS.txt`
can supply additional reviewed text and is preserved verbatim. Provenance is
packaged as `notices/REVIEWED_MODEL_PROVENANCE.txt`, distinct from the project-owned
`main/assets/notices/LOCAL_MODELS.txt`; both must survive packaging.

Eight external fixed texts are required: three runtime notices, the GGUF/Google
model cards, both PaddlePaddle model cards, and the full Apache standard license
from `https://www.apache.org/licenses/LICENSE-2.0.txt` (SHA256
`cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`).
Their URLs and digests are fixed in the preparer, and the APK gate verifies every
packaged text against the prepared inputs. A nonempty provenance text is not by
itself a licensing conclusion. Provisioning remains separate from an offline
asset recheck. Model downloads accept HTTPS only, reject credentials/downgraded
redirects, enforce file bounds/hash checks, and publish only complete verified
bytes. Existing matching model inputs are reused without network access; an
existing mismatched file is preserved and causes an error requesting a separate
task-owned source directory. Large weights remain outside Git.

Local preparation can reuse the existing pinned OCR files and a separately
downloaded new GGUF. Clone/copy the GGUF to the task directory's `models/` path
and the existing `local-models/{det.onnx,rec.onnx,det.yml,rec.yml}` to that task
directory's `.ocr-validation/models/`, then run:

```sh
python3 -B apps/muyon_android/checks/ci_model_inputs.py "$task_source" "$new_assets" --fetch
python3 -B apps/muyon_android/checks/ci_model_inputs.py "$task_source" "$new_assets"
```

The first command verifies/reuses all matching model bytes and fetches only
missing fixed inputs/notices; the second performs no network calls. Never use
the original user model directory as a replacement destination. Actual new-model
embedding/OCR inference, APK build and hosted CI results are separate evidence.

## Local verification and limits

- `python3 -B -m unittest discover -s apps/muyon_android/checks -p 'test_*.py'`:
  sixteen tests pass, including new corrupt/oversized input, non-HTTPS, credential,
  redirect and atomic publication checks.
- `sh -n apps/muyon_android/build-native.sh apps/muyon_android/build-ml-native.sh`:
  passes shell syntax validation.
- YAML loads with PyYAML; expected three jobs and both aggregate dependencies are
  present. `git diff --check` passes.

These are local checker/syntax results. No new full Gradle/native build or hosted
CI execution is claimed by this scoped resource/CI change. The integration owner
must record fresh build/device evidence on the fixed source SHA, publish/observe
the workflow run, verify the new official model candidate and obtain independent
review before changing the overall PARTIAL/HOLD status.

## Follow-up: real AGP asset collision and package-notice enforcement

Independent review found that the earlier CI provisioner emitted an external
`notices/LOCAL_MODELS.txt` while the product's main assets already owned that
relative name. Both directories belong to the same main source set; actual AGP
`AssetSet.loadFromFiles` raises `DuplicateDataException`, rather than overlaying
one notice. A nonempty ZIP notice check alone did not catch this.

The corrected provisioner preserves the external reviewed input text verbatim
under `notices/REVIEWED_MODEL_PROVENANCE.txt` and leaves the original source
`LOCAL_MODELS.txt` untouched. For an earlier script-owned output directory, it
migrates the old external filename only if its bytes match the preserved input.
A different old notice causes an explicit error and is retained for review.
No external licensing text is silently discarded.

`model_package_gate.py` now requires exactly one APK entry for each source local
summary, external reviewed provenance and all eight fixed model/runtime texts. It
compares each packaged text byte-for-byte with the appropriate input and reports
its SHA256. Missing, changed, duplicate, blank or colliding notices fail. Old
prepared assets/APKs without the new external provenance notice do not satisfy
this revised gate; historical PASS evidence remains tied to its earlier checker.
The OCR weights and fixed hashes are unchanged; the embedding uses the newly
verified official GGUF pin documented above. Text equality verifies
packaging integrity and does not itself establish redistribution permission.

Regression evidence on this host:

- Python checker suite after official provisioning changes: **16 tests pass**, including separate-name generation,
  lossless migration, conflicting-old-text preservation, and rejected missing or
  substituted local/reviewed package notices.
- The existing duplicate fixture reproduces **RED exit42** and actual AGP
  `DuplicateDataException`.
- The fixed provisioner's notice output, merged with the unchanged real product
  source asset directory through the checked-in `ModelAssetMergeRegression.java`,
  produces **GREEN exit0**, `AGP_ASSETSET_MERGE_PASS`.
- The diagnostic prints its actual loaded library: SDK Common **31.11.1** from
  AGP **8.11.1**, not a mock merger. The small diagnostic uses placeholder review
  text and mocks only weight preparation; it downloads or runs no model and
  makes no licensing claim. No full Gradle or native build was run for this check.

Raw diagnostics: `/private/tmp/muyon-ci-asset-review-20261021/repair/RED-rerun.log`
and `GREEN.log`. Re-run the real merger against prepared source directories with
the SDK Common31.11.1/dependency JARs on the classpath:

```sh
java --class-path "$classpath" \
  apps/muyon_android/checks/ModelAssetMergeRegression.java \
  apps/muyon_android/app/src/main/assets "$prepared_external_assets"
```

This diagnostic proves the asset namespace fix. A fresh APK build/package gate
and hosted CI execution on the integrated SHA remain separate verification.
