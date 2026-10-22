# Parent review corrective batch

Base delivery: 6cdaaa23ca1c194c0c32599cc1293f6c50907dcd.
Same independent branch; no shell, host, core owner or build file changes.

## Findings and fixes

Important 1: page failure trapped all navigation because readiness gated prev/next/location.
Regression first: pure ReaderNavigation boundary assertions and synthetic Android test cover
page1 -> Unknown annotation save -> transient FD failure on page2 -> enabled navigation and
explicit same-page retry -> page2 recovered with same draft/Unknown lock and one save only ->
another failed page -> previous page recovery -> document invalidation disables all navigation
and hides retry. Failed document reads before page count is known still have explicit retry.

Fix: distinguish LOADING / READY / PAGE_FAILED / ACCESS_LOST in the pure navigation policy.
Known page count and current authorization allow navigation after page errors. An explicit
readAttempt key restarts only the read producer; it does not remount ReaderContent or touch
editor sessions/save coroutines. Access/revision loss remains fail closed. No automatic retry,
new save intent or original unknown operation is sent.

Important 2: XLSX rPh descendant t was appended as cell/string value. Added exact inlineStr
and sharedStrings tests before parser change, including ordinary rich text after rPh and a
second cell/string to catch suppression leakage. Spreadsheet-only phonetic nesting counter
excludes hint text from base value; normal DOCX/PPTX text remains unchanged. Microsoft docs
identify rPh as a phonetic hint with parents is/si and t child, distinct from the base text:
https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.phoneticrun?view=openxml-3.0.1
Only this supplied official documentation page was opened, no search query or product API.

Minor: blank Highlight.note could not clear existing note. New tests expect empty/whitespace
highlight note -> null with original quote retained; Comment blank remains rejected and NUL/
UTF-8 size checks remain. Save enablement compares normalized replacement content to avoid
submitting whitespace when note already null.

## Frozen regression inputs

`3d2be1e783652735b79e9b58f6461d88ce131dc4` contains page recovery implementation and new
phonetic tests BEFORE phonetic fix. For verifier red/green use final Models/Checks with this
commit's OfficeTextPreview.kt (expect inline phonetic wrong-value assertion), then final
OfficeTextPreview (expect pass). For highlight regression, use final Office/Checks with this
commit's Models (expect blank-note assertion), then final Models (expect pass). Compile
before running; a compiler/setup error is NOT a behavioral red. Tests before page recovery
are retained in evidence/07-page-retry-test-first.log and Android test source; runtime absent.

Suggested normal verifier command from the final fixed commit:
`bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents/run-offline.sh`
with KOTLINC pointing to the existing approved compiler. No source from another work directory
is presumed. The parent separately reported original source JVM Kotlin2.2.20 -Werror JVM17
PASS; no raw verifier artifact was provided here, and this does not validate this new batch.

## Independent re-review and verification limits

Nonauthor reviewer `reader_review` independently inspected diff vs 6cdaaa23 and found no
remaining concrete finding. Confirmed navigation/retry authorization split, read-only retry,
retained unknown locks, phonetic scope/reset and normalized null-note edit behavior statically.
No edits by reviewer; compilation and runtime independently NOT_RUN.

Own new attempts are in evidence/10-review-fixes-verification.json: pure Kotlin and Android
checks NOT_RUN (exit2; no compiler/Gradle), whitespace check PASS. No red/green, APK, Android
SAX or Compose lifecycle execution claimed. Existing failure/NOT_RUN evidence is preserved.

Host contract remains strict: core save_annotation_trusted supplies annotation CAS only;
host additionally binds original anchor and persists original intent/receipt reconciliation.
The component does not fake that missing integration or assume core CAS is idempotent recovery.
