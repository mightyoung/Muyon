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
the embedding GGUF's complete origin and applicable model terms still require
review before any public model APK distribution. Runtime notices do not establish
model weight redistribution rights.

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

## Required CI configuration, currently a blocker

The repository previously recorded only a local filename and SHA256 for the
embedding GGUF. A complete public download source and reviewed provenance are
not established by that filename. The Android producer therefore requires a
repository variable `MUYON_MODEL_INPUT_URL` pointing to a reviewed, credential-free
HTTPS source directory. Missing configuration deliberately fails the Android job
and aggregate; it cannot produce a green product check. No credential or guessed
model source is introduced here.

The directory contract is:

```text
models/embeddinggemma-2-Q8_0.gguf
.ocr-validation/models/det.onnx
.ocr-validation/models/rec.onnx
.ocr-validation/models/det.yml
.ocr-validation/models/rec.yml
notices/LOCAL_MODELS.txt
```

The five model/config files must match existing `prepare-model-assets.py` sizes
and SHA256 pins. The Unicode dictionary is regenerated and the Android build
independently checks its fixed digest. `LOCAL_MODELS.txt` must contain reviewed
source/model-license notices; requiring a nonempty file is not license approval.
Runtime notices are fetched from the existing fixed URLs and checked against
their expected digests. Provisioning is separate from an offline asset recheck.
Downloads accept HTTPS only, reject credentials/downgraded redirects, enforce
file bounds/hash checks, and publish only verified complete bytes. Large weights
remain outside Git. Configure only after provenance review; no upload to an
external host or acceptance of new model terms has been performed by this change.

## Local verification and limits

- `python3 -B -m unittest discover -s apps/muyon_android/checks -p 'test_*.py'`:
  seven tests pass, including new corrupt/oversized input, non-HTTPS, credential,
  redirect and atomic publication checks.
- `sh -n apps/muyon_android/build-native.sh apps/muyon_android/build-ml-native.sh`:
  passes shell syntax validation.
- YAML loads with PyYAML; expected three jobs and both aggregate dependencies are
  present. `git diff --check` passes.

These are local checker/syntax results. No new full Gradle/native build or hosted
CI execution is claimed by this scoped resource/CI change. The integration owner
must record fresh build/device evidence on the fixed source SHA, publish/observe
the workflow run, resolve model-source configuration and obtain independent
review before changing the overall PARTIAL/HOLD status.
