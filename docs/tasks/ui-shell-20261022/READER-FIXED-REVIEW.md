# Reader fixed independent review

Reviewer: `/root/review_shell`, 2026-10-22. Fixed reader source `8d2b7931fa6b9194338ec81f1add8110075b92bc`; old regression slices `3d2be1e783652735b79e9b58f6461d88ce131dc4`. No reader production file was edited, no branch was merged and no real Service/model/search was called.

## Independent execution and script audit

Inspected `evidence/verify-reader-fixed.py` and the parent's four raw logs/results. Independently executed the same script source with only OUT redirected to a fresh temporary directory, preserving the parent's original logs. Compiler: actual Kotlin2.2.20, `-Werror -jvm-target17`; no Android stubs. The script extracts immutable real Models/Office parser/final Checks using git show and records content SHA256. All four independently recompiled successfully. Fixed full combination ran GREEN(exit0); old parser inline phonetic, isolated sharedStrings phonetic, and old Models blank-highlight cases each ran intended behavioral RED(exit1).

The isolated sharedStrings probe replaces only the earlier inline assertion with a print so execution reaches the later shared-string assertion. It is a test-only isolation probe, not unchanged final Checks or an old production mutation. Its distinct test SHA is recorded below. No compile failure is counted as RED. This is reverse regression on immutable slices, not evidence that every fix was originally developed test-first.

## Static page/UI review

ReaderNavigation distinguishes LOADING/READY/PAGE_FAILED/ACCESS_LOST. Known page count + PAGE_FAILED permits navigation; explicit readAttempt retries even an initial failure with unknown page count. Access loss disables navigation/retry. UI applies that policy to previous/next/go-to/retry. Retrying changes only the producer key and does not remount ReaderContent or editor map; existing annotation draft/UNKNOWN lock remain in the mounted component. Snapshot ref/URI/epoch/access keys fence component state. PDF/Office deliveries recheck host.isCurrent before and after rendering; PDF descriptors are bounded and closed. No automatic save/retry is added.

Spreadsheet phonetic suppression is limited to spreadsheet modes, handles nested rPh depth, then allows subsequent rich text and next cells/strings. Blank highlight notes normalize to null without discarding quote; blank comments remain rejected; UI compares replacement content before enabling save.

No new Important issue was identified in this bounded static review.

## Coverage limits and missing host

Only DocumentReaderModels, OfficeTextPreview and DocumentReaderChecks execute in this JVM evidence. DocumentReaderScreen, NativeDocumentPreview, Android PdfRenderer, Android SAX behavior, Compose, actual page IO recovery/editor retention, Activity recreation, font scaling, IME/Back/TalkBack and FD lifecycle are NOT verified by these runs. Page policy assertions pass in the fixed suite, but these four combinations do not establish a pre-navigation-fix behavioral RED: commit3d2 already contains navigation recovery. Existing Android test source/NOT_RUN stays NOT_RUN.

The host bridge has not arrived. No real authority resolution, byte-delivery grant validation, sidecar durable intent/receipt recovery or integration success is claimed. The component's host closures must implement those obligations before production use. Office output is bounded text preview, not native-layout reading/editing or a fidelity verdict. Deferred advanced format capability remains unavailable.

## Source identity and independent raw results

Script SHA256: `545c5efe35716277e6d3ba75706bba8aff5d4bec4c5a3785caf0717207c27e45`. Fixed DocumentReaderScreen SHA256 (static-only): `0f7fbd9da0fe6ec22f93326f4098fb73fff2a643958dda78f696bdb9334cbe47`.

### reader-fixed-all-green

```text
command=["/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc", "-Werror", "-jvm-target", "17", "/tmp/muyon-reader-fixed-0xscx2e7/DocumentReaderModels.kt", "/tmp/muyon-reader-fixed-0xscx2e7/OfficeTextPreview.kt", "/tmp/muyon-reader-fixed-0xscx2e7/DocumentReaderChecks.kt", "-include-runtime", "-d", "/tmp/muyon-reader-fixed-0xscx2e7/checks.jar"]
sources={"DocumentReaderModels.kt": "cddb2403725a102287fd4980d6ea8ca2b07fce479d2cd1386b5a6c97709d8440", "OfficeTextPreview.kt": "37efc87a9dbee0172e8c4ee68599820ebbd6c6a72a86bf8fd4114989c8c1fc23", "DocumentReaderChecks.kt": "30b9695fb135a43cb069cb1a9c97c741e6639a712a3855faaeb75a275b94040f"}
models_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
parser_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
checks_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
isolated_shared_probe=False
compile_exit=0
runner_exit=0
PASS: reader state, sidecar CAS and bounded native Office text checks
```

### reader-inline-phonetic-red

```text
command=["/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc", "-Werror", "-jvm-target", "17", "/tmp/muyon-reader-fixed-2g6h8shl/DocumentReaderModels.kt", "/tmp/muyon-reader-fixed-2g6h8shl/OfficeTextPreview.kt", "/tmp/muyon-reader-fixed-2g6h8shl/DocumentReaderChecks.kt", "-include-runtime", "-d", "/tmp/muyon-reader-fixed-2g6h8shl/checks.jar"]
sources={"DocumentReaderModels.kt": "cddb2403725a102287fd4980d6ea8ca2b07fce479d2cd1386b5a6c97709d8440", "OfficeTextPreview.kt": "8135ca11ed6ac8ee4570e10f2c9798dc60451ca39a063c26764753a208f48e7b", "DocumentReaderChecks.kt": "30b9695fb135a43cb069cb1a9c97c741e6639a712a3855faaeb75a275b94040f"}
models_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
parser_commit=3d2be1e783652735b79e9b58f6461d88ce131dc4
checks_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
isolated_shared_probe=False
compile_exit=0
runner_exit=1
Exception in thread "main" java.lang.IllegalStateException: A1: 東京とうきょう駅
B1: next

	at com.mightyoung.muyon.product.ui.documents.DocumentReaderChecksKt.main(DocumentReaderChecks.kt:73)
	at com.mightyoung.muyon.product.ui.documents.DocumentReaderChecksKt.main(DocumentReaderChecks.kt)
```

### reader-shared-phonetic-red

```text
command=["/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc", "-Werror", "-jvm-target", "17", "/tmp/muyon-reader-fixed-6chwq07b/DocumentReaderModels.kt", "/tmp/muyon-reader-fixed-6chwq07b/OfficeTextPreview.kt", "/tmp/muyon-reader-fixed-6chwq07b/DocumentReaderChecks.kt", "-include-runtime", "-d", "/tmp/muyon-reader-fixed-6chwq07b/checks.jar"]
sources={"DocumentReaderModels.kt": "cddb2403725a102287fd4980d6ea8ca2b07fce479d2cd1386b5a6c97709d8440", "OfficeTextPreview.kt": "8135ca11ed6ac8ee4570e10f2c9798dc60451ca39a063c26764753a208f48e7b", "DocumentReaderChecks.kt": "4e9d4e6df55486298d42a26d0ee8efde2c87580b73ceab5191c802586c87989c"}
models_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
parser_commit=3d2be1e783652735b79e9b58f6461d88ce131dc4
checks_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
isolated_shared_probe=True
compile_exit=0
runner_exit=1
isolated sharedStrings probe: preceding inline actual=A1: 東京とうきょう駅
B1: next

Exception in thread "main" java.lang.IllegalStateException: A1: 東京とうきょう駅
B1: next

	at com.mightyoung.muyon.product.ui.documents.DocumentReaderChecksKt.main(DocumentReaderChecks.kt:77)
	at com.mightyoung.muyon.product.ui.documents.DocumentReaderChecksKt.main(DocumentReaderChecks.kt)
```

### reader-highlight-empty-red

```text
command=["/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc", "-Werror", "-jvm-target", "17", "/tmp/muyon-reader-fixed-2j_pyvfj/DocumentReaderModels.kt", "/tmp/muyon-reader-fixed-2j_pyvfj/OfficeTextPreview.kt", "/tmp/muyon-reader-fixed-2j_pyvfj/DocumentReaderChecks.kt", "-include-runtime", "-d", "/tmp/muyon-reader-fixed-2j_pyvfj/checks.jar"]
sources={"DocumentReaderModels.kt": "3490ae6294d954c606dbf89d5beba6f62ed1cee4551f0eb5bab3cf33b32c8cf9", "OfficeTextPreview.kt": "37efc87a9dbee0172e8c4ee68599820ebbd6c6a72a86bf8fd4114989c8c1fc23", "DocumentReaderChecks.kt": "30b9695fb135a43cb069cb1a9c97c741e6639a712a3855faaeb75a275b94040f"}
models_commit=3d2be1e783652735b79e9b58f6461d88ce131dc4
parser_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
checks_commit=8d2b7931fa6b9194338ec81f1add8110075b92bc
isolated_shared_probe=False
compile_exit=0
runner_exit=1
Exception in thread "main" java.lang.IllegalStateException: Check failed.
	at com.mightyoung.muyon.product.ui.documents.DocumentReaderChecksKt.main(DocumentReaderChecks.kt:47)
	at com.mightyoung.muyon.product.ui.documents.DocumentReaderChecksKt.main(DocumentReaderChecks.kt)
```
