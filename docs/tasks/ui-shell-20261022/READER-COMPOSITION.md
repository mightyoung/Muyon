# Released reader composed into production source set

Parent released exact reader8d2b7931fa6b9194338ec81f1add8110075b92bc after its static
review plus the actual JVM regressions in shell08e77d05647afc47b99ec839f846eba5163bf6c7.
Ordinary merge935d48b2350d7dd6bfb065068c5db102c462d09d on task/ui-shell-20261022 includes
that immutable reader branch. No main/develop merge; Leader B retains final integration.

Reader source, pure tests and Android tests are byte-identical to8d2b7931. Confirmed:

```bash
git merge-base --is-ancestor 8d2b7931fa6b9194338ec81f1add8110075b92bc HEAD
git diff --exit-code 8d2b7931fa6b9194338ec81f1add8110075b92bc HEAD -- \
 apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/documents \
 apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents \
 apps/muyon_android/app/src/androidTest/kotlin/com/mightyoung/muyon/product/ui/documents
```

Both exit0. Existing Gradle app source discovery now includes the actual reader components
for future production compilation; this is not a connected live reader route.

Only shell-owned DocumentCapabilitiesScreen and its existing instrumentation target
change: public reading accurately waits for an authorized file/version bridge; PDF
page versus Office text-preview limits are explicit; sidecar edit/save remains disabled
pending permission/version/receipt checks. Existing project-material navigation is kept.
No selected document, URI, DocumentReaderHost, open descriptor, static true permission
closure, save success or live annotation is constructed. Reader components remain under
their original owner's control. MainActivity already routes the public-document menu here.

## Actual combined-tree verification

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents/run-offline.sh
```

Exit0; actual Models/parser/full Checks PASS. Raw evidence/reader-composed-green.log.
The prior immutable reverse-regression REDs/GREEN and independent rerun are retained in
READER-FIXED-VERIFICATION.md and READER-FIXED-REVIEW.md, rather than overwritten.

From apps/muyon_android, actual combined production source set:

```bash
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
./gradlew --offline --no-daemon --console=plain :app:compileDebugKotlin \
 :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest
```

Exit1 before product compilation, still com.android.application8.11.1 unresolved from
configured plugin repositories. Full evidence/reader-composed-android.log. Kotlin Android/
Compose/test compilation, instrumentation, PDF/SAX Android execution and APK remain NOT_RUN.
Unexecuted instrumentation expectations were updated; this is not a behavioral TDD pass.
SDK read-only failure remains untouched: no install retry, permission/security/network
change, credential, alternate resolver, paid CI/SDK, real model/search request or bypass.

Independent bounded composition review: READER-COMPOSITION-REVIEW.md. Scoped source/docs
whitespace validation excludes the preserved raw Gradle log's original trailing space.

## Remaining host implementation

READER-WIRING-REQUEST.md still gives the exact callback request. Original host/core owner
must deliver shared-store authorized metadata, controlled read-only seekable FD, live
scope/grant/revision invalidation and durable original sidecar intent/receipt recovery.
The reader's core schema dependency f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac is not an
Android authority/FD gateway. Its host implementation is not synthesized by this merge.
Ordinary ContentResolver access and old research private cache are not substituted for
those checks. Formal document edit/save and full Office fidelity remain unavailable.
Whole UI development/Android acceptance remain open; no historical unknown request or
¥0.002620 reservation is queried, retried, changed or settled by this work.
