# Exact reader intake and single-writer host request

2026-10-22 UTC. Shell production slice is already fixed/pushed at
5186917c49a6d4772ac97643430ff14c9fdabc16. This follow-up reads reader source without
merging it pending the parent's independent release; it does not change reader,
service/runtime/research/native/manifest files or claim production document integration.

## Verified immutable input and actual check

Remote refs/heads/task/android-document-reader-20261022 and FETCH_HEAD both equal
6cdaaa23ca1c194c0c32599cc1293f6c50907dcd. Read HANDOFF/REPORT, DocumentReaderModels,
DocumentReaderScreen, SharedDocumentJson and the executable pure-check source.
Core identity/schema dependency named by reader is f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac;
this is not a delivered Android authority/byte bridge.

Extracted exactly DocumentReaderModels.kt, OfficeTextPreview.kt and
DocumentReaderChecks.kt using git show at that fixed SHA into a new task temp directory.
Compiled using the existing verified Kotlin2.2.20 executable, -Werror -jvm-target17,
-include-runtime. Executed the actual resulting jar. compile_exit=0, runner_exit=0:
`PASS: reader state, sidecar CAS and bounded native Office text checks`.
Raw evidence: evidence/reader-6cdaaa-pure.log. No generated stubs, native renderer,
Android/Compose/FD tests or third-party engine were executed. This supplements the
reader author's NOT_RUN records; it does not replace them with an APK result.

## Exact factory/callback request to parent and host owner

The shell can call the existing component unchanged:
`DocumentReaderScreen(snapshot: DocumentReaderSnapshot, host: DocumentReaderHost, onClose)`.
Please assign the original authority/native/host owner a concrete Android document host
factory, with these capabilities and an exact reviewed commit before shell integration:

1. **List/select one authorized document**: one shared store's actual DocumentRef and
   annotation records, selected by current actual workspace/project/document identity.
   Do not derive document IDs from paper titles or synthesize revisions/digests. Preserve
   revisions as unsigned decimal wire strings. Missing metadata stays unavailable.
2. **Live snapshot**: controlled content URI for that exact immutable blob,
   hostEpoch/accessActive, and core-projected annotations. Publish revocation/expiry/
   scope/project/source deletion while the reader is idle; static true is insufficient.
3. **openCurrent(ref, uri, epoch)**: suspend typed callback returning a new READ_ONLY,
   seekable ParcelFileDescriptor for exact source after checking active DocumentAccess,
   generation/grant/scope/project/revision, permitted operation and actual-byte MIME/safety.
   Do not allow an arbitrary path or ambient unverified ContentResolver open.
4. **isCurrent(ref, epoch)**: authoritative recheck at start, after parse/render before
   delivery, and around save; deny old epochs/revisions. Host owns invalidation publication.
5. **saveSidecar(edit, epoch)**: trusted host derives actor, parses exact shared anchor,
   checks unchanged document/anchor and expected annotation revision, calls the shared
   save_annotation_trusted operation with durable original intent/receipt. Saved means
   confirmed committed core result, Rejected means definite noncommit, Unknown retains
   original identity and prevents another write. Return refreshed actual snapshot.
6. **Re-entry reconciliation**: before enabling another annotation edit/save after close,
   process death or scope/epoch change, reconcile the prior durable original intent.
   A component-only memory lock is insufficient. If host supports read-only preview first,
   explicitly negotiate a reader-owned edit-capability gate rather than displaying an
   enabled save action that lacks a real gateway; shell must not fake Saved or permissions.

Existing ProductClient/Service carry JSON Messenger responses, not PFD objects.
Existing ResearchFileHost.attachment uses paper+digest, obtains reader_id, copies bounded
bytes to a private cache file and closes the reader. It is not this shared DocumentAccess/
revision/epoch/idle-invalidation bridge and must not silently be cast into one. Current
manifest has no ContentProvider. Parent must coordinate any necessary typed IPC/provider/
FFI work with its existing owner; shell will not add a provider, modify permissions or
regenerate bindings independently. A controlled URI is descriptive metadata, not authority.

## Shell-only executable sequence after reviewed host delivery

- Compose the parent's exact released reader and host dependency graph on this feature
  branch; avoid duplicating already integrated foundation/core histories.
- MainActivity's public-document route displays the actual authorized listing. Selection
  opens the supplied snapshot/host pair; no fixture records or invented identity.
- Shell navigation retains the exact selected ref/epoch and lets host invalidation close
  access. Back/close cancels only the mounted view, not an uncertain durable save.
- Source-card/search navigation consumes exact authorized source version/anchor; zero-based
  core PDF page becomes a one-based display only with bounds. Reader currently has no
  initial-position parameter: request that small change from its owner when actual source
  navigation is ready; do not create an unrelated source or pretend title matching is location.
- Run pure bridge/callback tests before implementation, then actual Android compile/device
  commands when the previously recorded AGP/SDK blockers can be resolved through authorized
  means. Old f478 device evidence and source illustrations are not new UI evidence.

Ownership: shell keeps MainActivity/ChatScreen/ui/shell; reader owner exclusively maintains
ui/documents and its tests; host/core owners exclusively provide authority, document storage,
service/native bridges and durable receipts. main/develop and historical unknown requests/
¥0.002620 hold remain untouched. No network model/search, credentials, paid SDK, new engine,
permission expansion or workaround of the SDK read-only failure.
