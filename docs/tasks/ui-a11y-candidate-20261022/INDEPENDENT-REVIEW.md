# Independent review: minimal UI candidate and actual product packaging

Fixed source `708570d59ea51024ee69bb62c97f63380d490f78`, direct parent
`c130008bbc40d78e85d10058030da9da4aca38f0`. No blocking or Important finding in
the minimal source change or verified packaging evidence. This review does not
approve a develop merge, deployment, redistribution beyond recorded notices, or
full product runtime/inference acceptance. Reviewer writes only this report;
no source/tool edits, device operation, model inference or network requests.

## Source and dependency scope

Full base-to-candidate source diff is exactly three files,36 additions/5 removals:
ConversationShell.kt, ShellInputDock.kt and ConversationShellTest.kt. It adds stable
draft purpose, heading and polite live-region semantics, plus two additive tests.
No Host/Core/FFI/binding/permission/capability gate, action, token, dependency version
or business state changes. All required Compose APIs are already in the base.
Three blobs equal the previously reviewed043bed blobs; no old branch history is
merged. Base's existing recursive JSON comparator remains unchanged. Base already
has PdfDocument.useClosing with finally close; acfa resource fix is not repeated.
Working production/checks/crates/workflow files remain identical to fixed708570.

New real Android production plus full androidTest Kotlin compile succeeded in
1m53s,27/27 tasks executed. Separate component assemble succeeded1m50s,62/62 tasks
executed. Independently compared all18 component source-manifest copies to fixed
708570 git objects:18/18 exact. Actual component device instrumentation contains
10 unique status0 results, exactly matching six Shell and four Reader source test
methods, no failed/omitted method, OK(10 tests),90.657s, normal terminal code-1.
Install/environment log records both Success, boot1/API26/x86_64/1080x1920/420dpi/
font1.0. These are component tests with synthetic UI/PDF/host callbacks, not a
full product MainActivity/Service/authoritative ReaderHost/FFI or model runtime test.

Original external-runner failures remain real archived failures: raw-Iterator
2013 JSON fork compilation mismatch, and configuration runner missing the existing
SetupDraftArchive source. Canonical JSON-java Host runner has three PASS groups;
full actual-source configuration runner has5/5 PASS. These do not retroactively
make the two original invocations pass. TalkBack speech is not established.

## Public fixed model inputs and provenance

Independently rehashed all six actual provisioned model/config assets against
model-manifest.json: all sizes and SHA256 match. Read-only local recomputation
from real rec.yml using the unchanged prepare-model-assets.py transformation
produces dictionary bytes exactly: [empty string]+PostProcess.character_dict+
[space],18385 entries, UTF8 ensure_ascii=False compact JSON,110788 bytes,
SHA256 d858428fbe0ada92b439a5f277b51bc1b318fd985d80946a3ce859d7f2446a92.
MODEL-LICENSE-NOTICE correctly identifies it as Muyon-derived, not upstream's
original same-named file, and marks that transformation.

Local fixed GGUF/OCR model cards all contain Apache2 license metadata. Upstream
.src_sha records PRIMARY914f7f89142e33e77833254d9c9b90c3cef7303b, and archived LFS
pointer matches actual309855456-byte GGUF hash2188ac1d…b09135. Original fixed full
upstream conversion log hashes900fc30b02d8e424eacdd1ce58687b6449b2587733e03e63c18fe5ed77009e1a;
it actually contains version0.6.0-dev/build11451/commit1e91a0b05. Initial excerpt
missed that line due CR/LF indexing; author corrected the archived excerpt to the
actual version lines before sealing. This is upstream-stated provenance, not an
independent reproduction of conversion or proof of all build dependencies.
The supplemental notice explicitly corrects inherited APK notice uncertainty;
original APK notices and model bytes remain unchanged. No legal conclusion beyond
the recorded license/provenance text is inferred from a model hash.

## Actual complete product build and independent static checks

Final clean offline product command terminates BUILD SUCCESSFUL2m17s,78/78 tasks
executed, including clean, assembleDebug, assembleDebugAndroidTest and lintDebug.
Exit record is0. Prior failed missing-assets, missing lint dependency, host SQLite
linking, PATH and cargo-cwd attempts remain archived; none is claimed successful.
Final binding generation completed (ktlint formatter unavailable warning remains);
independent package gate confirms generated and checked-in bridge byte equality.
Real system SQLite linkage was a task-local development symlink to the existing
system library, not an Android substitute; packaged product readelf gate rejects
hidden Android SQLite dependencies. Native build log completes both real ABI and
llama outputs. No production gate or model input was stubbed or disabled.

Reviewer independently reran both unchanged static gates against the final APK:

```text
ANDROID_HOME=/workspace/ui-shell-tools/sdk
python3 apps/muyon_android/checks/package_gate.py
  apps/muyon_android/app/build/outputs/apk/debug/app-debug.apk
  /workspace/ui-shell-tools/candidate-product-native/jni
  /workspace/ui-shell-tools/candidate-generated/com/mightyoung/muyon/productbridge/muyon_android_product.kt
  apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/productbridge/muyon_android_product.kt
python3 apps/muyon_android/checks/model_package_gate.py
  apps/muyon_android/app/build/outputs/apk/debug/app-debug.apk
  /workspace/ui-shell-tools/candidate-model-assets
  /workspace/ui-shell-tools/candidate-product-native/jni
```

Both **exit0 / gate PASS**. First confirms source build identity, exact bridge,
ABI/native bytes and ELF/APK16KiB alignment. Second confirms six actual model files,
ten fixed model/runtime/provenance notice byte sequences and packaged library alignment. Output JSON
SHA256 respectively bcc8b078e2440a8e5cd9ed3421758837a2a60c36d8451dab62ed27e16ff2e781
and f447bece6388d907a3e936144edf50147aeda0cd842047fc30a994ef2579fd4d.
Reviewer also ran official build-tools35 apksigner verify --verbose: exit0,
Verifies, v2 signature true, one signer. No SourceStamp; not a store signature claim.

Final artifact bytes independently rehashed:

- Product debug APK426369208 bytes:
  `f1cc240fd981a1ea08841f3964c6422e5b240268984447022406428723ddeb0b`.
- Product androidTest APK1439740 bytes:
  `fa0c08ed932d8a28f439601a224e45c0a4854ad73ec3983d6ef396287ba01d1d`.
- Native build identity:
  `708570d59ea51024ee69bb62c97f63380d490f78:95d79703ba3b05f9af3020118286fb5559f17c7042d183cee394074dc25ae811`.

## Acceptance boundary

A real complete debug product APK is now built and statically verified; earlier
missing-assets packaging blocker is resolved for this candidate. Its runtime
identity, install/start, model inference and authoritative business/ReaderHost/FFI
chain have **not** been validated here.16KiB static alignment is not execution on
a16KiB kernel. Component10/10 device results cannot be transferred to the product
APK. No new current-source product screenshots or model execution are claimed.
The ZIP was subsequently checked as recorded below; Library upload/publication
is not performed or certified by this review. Main/develop and PR101 remain outside this worker's write scope.


## Final report and prepared ZIP closure

Reread the completed REPORT and MODEL-LICENSE-NOTICE after final logs/gates were
archived. They correctly distinguish real complete product packaging success from
the earlier component10/10 device evidence and unexecuted product/inference chain.
The quantizer excerpt now includes its actual version lines. Final report retains
original failed commands and narrows Lint provenance to32 added official artifacts,
not770 newly downloaded files. No scope inflation or remaining blocking report
issue found.

Independently inspected the prepared ZIP without executing its APK. ZIP size
426435555 and SHA256624602da28f84fbaf25c2ebe2c031ddbb5a8dc8d2323e6d94e2541a800fa246e
match deliverables.json. It has no duplicate entries; embedded APK SHA256 equals
final product f1cc240f…deb0b and copied APK is identical by size/hash. All11 actual
APK assets/notices/*.txt are copied byte-for-byte into ZIP licenses/, including
notices beyond the ten model-gate entries. Readable MODEL-LICENSE-NOTICE companion
also equals the reviewed repository document exactly. deliverables.json explicitly
states uploaded=false: prepared, not uploaded/published/delivered. Parent still
decides delivery timing. This check does not run APK code or extend runtime claims.

Sealed reviewed input SHA256:

- `REPORT.md`: `dcebc1a04c2a0fedc62693335de65ebeff8954d119380508d69d7024b6b15ceb`
- `MODEL-LICENSE-NOTICE.md`: `7db20b62de509eefc822fcacfaaf3181f918bd490cecca4aad1a50383503e5c4`
- `evidence/product-final.log`: `764c3bf5bdb36588b9dc514de687441fe065e443de22337b67cc4e0c5d65e5b3`
- `evidence/product-final-exit.txt`: `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa`
- `evidence/package-final.json`: `bcc8b078e2440a8e5cd9ed3421758837a2a60c36d8451dab62ed27e16ff2e781`
- `evidence/model-package-final.json`: `f447bece6388d907a3e936144edf50147aeda0cd842047fc30a994ef2579fd4d`
- `evidence/product-signature.log`: `869bfea9bfdb6c24e760e419a633d296cb478f6e0c8ff84e2b1350533f09c6c8`
- `evidence/model-manifest.json`: `5a16b32336f65d6802ba5f862ccbcd0e5b0f28140cb1867d9fcb5ee03ca232ff`
- `evidence/provenance/sources.json`: `f7a91a5d8ce7cf1afab186e9163372b1f8ad207c86b982b51cd5dfd7f6461ccf`
- `evidence/provenance/quantizer-version-excerpt.txt`: `a69adab4bd35064c45f365fc3cfe79ea87f651a90ccf936299e7e84d400836d7`
- `evidence/deliverables.json`: `efe407aa619748e8d183e911cc5406fd34257cb74f07a8438b0aefaa0d6a19a8`
