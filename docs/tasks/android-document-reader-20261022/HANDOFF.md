# Shell / host wiring contract

Callable UI is `com.mightyoung.muyon.product.ui.documents.DocumentReaderScreen`:

```kotlin
DocumentReaderScreen(snapshot: DocumentReaderSnapshot,
                     host: DocumentReaderHost,
                     onClose: () -> Unit)
```

No shell/host/core owner file is changed. Shell owner replaces its existing disabled
public-reader route with this component after host owner exposes the callbacks below.
This is real component code, not a wired production route or a completed authority adapter.

## Read data from the one shared store

Pin core dependency to `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac` (do not infer another
working directory). `SharedDocumentJson.document(JSONObject)` maps serde DocumentRef:
`scope.workspace_id`, nullable `scope.project_id`, `document_id`, decimal-string `revision`,
`format` (`pdf/docx/pptx/xlsx`). `SharedDocumentJson.annotation(JSONObject)` maps core
AnnotationRecord including original anchor, own decimal revision, body, created_by,
modified_by, deleted, anchor_state. No revision is converted through Double or Long.

Host obtains metadata from `BusinessStore.read_document(&DocumentAccess)` and annotations
from `list_annotations(&DocumentAccess)` using the existing core owner. It selects the
controlled content URI for that exact immutable blob. URI is metadata, never authority.
Snapshot includes hostEpoch, accessActive and annotations; emit a new epoch/accessActive=false
on revoke/expiry/deletion/scope change, including while the reader is idle. UI excludes other
workspace/project/document/format annotations and displays same-document older revisions as
stale, never attaching them to current geometry. It retains raw core anchors, not a new DB.

`DocumentReaderHost` requires three concrete host-supplied suspend callbacks:

- `openCurrent(ref, contentUri, epoch): ParcelFileDescriptor`: recheck source/blob safety,
  current exact DocumentAccess, active persisted grant/expiry/generation/project/scope/revision,
  and operation permission on each invocation; return a new READ_ONLY seekable FD for PDF.
  Reject arbitrary paths, unrelated content URI, stale revision or missing permission.
  Do not use ambient ContentResolver.openFileDescriptor without those checks. Platform
  PdfRenderer takes the FD for one page and closes it; Office takes ownership via
  AutoCloseInputStream. FD failures are surfaced; no network/download fallback.
- `isCurrent(ref, epoch): Boolean`: authoritative check at read start and after render/parse,
  before delivery to UI, and around save callbacks. It must not be a cached reusable permit.
  Host must publish invalidation while idle; a static true closure is only valid in synthetic tests.
- `saveSidecar(edit, epoch): SidecarSaveResult`: create/reuse a durable host intent, verify
  expected annotation revision and unchanged document/anchor, derive actor from trusted host,
  parse `edit.anchorJson` as shared DocumentAnchor and use `SharedDocumentJson.replacementBody`.
  Call `BusinessStore.save_annotation_trusted(&DocumentAccess, annotationId,
  &Revision, &DocumentAnchor, &AnnotationBody, &AnnotationAuthor)`; never write annotation SQL
  or source file bytes directly. `Saved` requires confirmed committed core result; publish
  refreshed annotations/revisions. `Rejected` is a definite noncommit. Lost/ambiguous response
  is `Unknown`; query that original intent/receipt, do not issue a fresh write.

UI submission locks/drafts survive page loads within the reader. Reentering after close,
process death, scope/epoch change, or host callback cancellation REQUIRES host durable intent
reconciliation before authorizing another save. This component cannot manufacture durable
receipt recovery; the host owner owns it. A changed immutable annotation revision resets
that annotation editor; same revision must not be changed in-place by a host snapshot.
No callback is invoked for PDF text selection/new selection anchors/native annotation writes.

## Reader behavior and limits

PDF: actual Android PdfRenderer page pixels, previous/next, one-based page input clamped to
available pages, 100–300% zoom with horizontal/vertical scrolling. Each render uses a new
short-lived FD; one ARGB page is capped at 1,048,576 pixels. No OCR/text extraction/selection,
embedded annotation, encrypted-document unlock, editing of source bytes or flattening.
No thumbnail/index/cache/outbound request is introduced. Platform native reader is authorized;
no isolated HOLD third-party engine is run or unblocked.

DOCX: main `word/document.xml` text paragraphs only.
PPTX: text from numbered `ppt/slides/slideN.xml` parts only.
XLSX: numbered worksheet cell refs, inline/shared strings and raw/cached values only;
formula values explicitly labelled cached, never calculated. Section labels expose exact ZIP
part names; numeric part ordering is NOT presentation/workbook tab order. Dates/styles,
merged cells, layout, graphics/charts, notes, external links and embedded objects unsupported.
This is supported text preview, not Office page rendering or full OOXML validation. Source
MIME/safety must be host-verified against actual bytes, not metadata/extension alone.

Native ZIP/SAX parser bounds: 16 MiB compressed, 32 MiB expanded, 4 MiB selected part,
1024 entries, 64 sections, depth128, 200000 text chars, 10000 shared strings. Unsafe/duplicate
selected paths, malformed XML, DTDs/entities or missing selected parts fail. Platforms unable
to enforce SAX entity/lexical restrictions fail closed as unsupported. No ZIP extraction to disk,
network/entity resolution, macros, commercial SDK or added dependency.

## Verification commands (existing tools only)

```sh
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/documents/run-offline.sh
bash apps/muyon_android/gradlew -p apps/muyon_android :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin --offline
# Full device suite requires fixed approved native/assets and existing SDK/device:
bash apps/muyon_android/gradlew -p apps/muyon_android :app:connectedDebugAndroidTest --offline
```

Retained tests: pure Kotlin state/CAS/scope/revision/ZIP/XML behavior; Android synthetic
PDFs check distinct actual page colors, invalid page error, exact core JSON projection,
and pending-save → flip → Unknown → flip-back preserves lock/draft and excludes foreign scope.
All compiler/device results remain NOT_RUN in this environment; no green TDD or APK claim.
