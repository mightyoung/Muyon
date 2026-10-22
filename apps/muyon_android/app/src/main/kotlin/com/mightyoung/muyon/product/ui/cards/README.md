# Action cards — controlled Compose projections

This directory contains display DTOs and seven native Compose surfaces: `AttachmentCard`, `EvidenceCard`, `ChoiceCard`, `DraftCard`, `ConfirmationCard`, `ReceiptCard`, and `ProjectCards`. There are no default business records, network/IPC methods, automatic submissions, grants, persistence or business reducers. All fixture records live in test sources. Chinese labels implement the supplied design; localization extraction is a future host task.

## Fixed inputs and prerequisites

Candidate verified at `f4781e16ddf4e542b983fbd77f266a0071148255`. Actual design images 03/04/05/07 and the full UI specification were read from design-intake `399e3094740c8fcf1783797f0d0ae1f076dfd123`; later archive `400e206135690c284c8402521e3135cfb7bfaee8` adds original brand assets. This feature needs no mascot/logo copy. Original images are design references, never execution evidence.

The fixed prerequisite `task/ui-foundation-20261022` at `2aa95ba7ab74ea11f9a89a42d2568650363e6c17` is merged into this task branch following explicit dependency-combination authorization. Cards use its `FoundationButton` and `FoundationTag` and inherit its theme. The shell must wrap cards in `FoundationTheme` (soft light/dark palettes); no local token copy or replacement application theme is introduced. These dependency files are unmodified by the cards writer. Both prerequisite and cards still require real Android compilation/rendering.

`task/chat-component-contracts-20261022` at `c7c0d4729d034eb3d644e8945a56ca7dba467ff4` was inspected but is NOT merged. The parent reported a scope-only `requestCancel(scope)` late-attempt bug and a pending full-identity/CAS repair. Do not wire the old cancellation API. The cards have no reducer dependency and do not call it. The repaired fixed source `52576777716ea215ef1428b4dc0bcd65fde17f00` was subsequently read: `requestCancel(scope, pendingIdentity, expectedRevision): PendingSubmission` checks full pending identity and CAS, and only records local cancellation intent. Map the current binding stateRevision to expectedRevision and reconstruct pendingIdentity exclusively from OriginalCardRequest (including its original binding). Do not reconstruct pending identity from the latest attempt. Parent static closure and production host wiring are still pending; no contract source was merged here.

## Identity and callback boundary

`CardScope` is a rendering copy of the trusted host scope, including workspace, conversation, optional project, agent and mounted generation. `CardBinding` includes this scope, component/message IDs, component/state revisions, attempt and host-supplied digest. The digest is opaque; never derive it from displayed labels, and never use the local component draft digest as a substitute for business/disclosure payload digest.

`OriginalCardRequest` retains the exact original binding, action and intent independently of the current CAS binding. Query/cancel callbacks carry BOTH values. A receipt card can display history from an earlier attempt; the host must reject a cancellation whose original identity is not its current pending identity even if the displayed scope matches. It must also compare the expected state revision, component revision and mounted generation atomically. Cards only transport these facts and cannot enforce durable host CAS. No scope-only cancellation, intent substitution, automatic retry or fee cleanup is allowed.

`CardInteractions.capabilities` is a host-supplied presentation allowlist, default empty; missing callbacks render disabled controls. This is not authorization. For every callback the shell must recheck current identity, scope, permission, revision, snapshot and expected action against trusted host state. Never decode model Markdown into these trusted DTOs or dispatch callback names as IPC methods.

| Callback category | Behavior to implement in host |
| --- | --- |
| `LocalDraft` | Selection/field edit, save draft, edit report, dismiss preview; no send or business approval |
| `OpenSource` | Resolve source/document revision+anchor under scope; do not infer evidence truth or cross-project access |
| `ExternalLink` | Separate external navigation policy; validate destination and ask when existing host policy requires |
| `MessageSend` | Explicit send gesture; existing outbound preview/cost/disclosure gate still applies |
| `BusinessPreview` | Prepare a new trusted submission/save preview; never persist a business change from this event alone |
| `BusinessExecution` | User requests execution of the exact trusted preview; validate modification/disclosure kind and all original fields, then use existing host gate |
| `ReceiptQuery` | Query exact original intent; never create a replacement request |
| `Cancellation` | Request cancellation of exact pending identity with CAS; no implied success or rollback |

The presentation state is entirely caller-controlled. Save clicks do not switch a card to saved. Only a verified host draft receipt may set `DraftSaveStatus.Saved`. Unknown or saving locks local edits/save/submit/send; the host should show the matching `ReceiptCard` for recovery. Selection does not persist or send. No fields in a confirmation change locally; changed target/content/scope/digest/revision must yield a new trusted preview and invalidate the old one. `Modification` and `Disclosure` carry distinct kind/labels; disclosure requires nonblank actual content and an explicit recipient.

Attachments render each supplied stage and its detail separately, including partial and unknown. They never manufacture a percent or infer that saved means fully read/indexed. Evidence separates cited sources from retrieval candidates and always carries a source revision/anchor. Missing anchor disables locate; an external URL has a distinct callback. Provenance is supplied by the trusted host and never inferred as independent support. Costs preserve nullable reserved/actual values as unknown, not zero.

Project materials are immutable snapshot references. Report draft actions are edit/preview new-version save; historic/saved versions are view-only; conflict offers view/compare and no edit/save. Actual append-only storage and conflict resolution belong to the host.

## Contract mapping reserved for the unique ui-shell owner

| Existing contract | Display mapping / remaining host work |
| --- | --- |
| `ComponentScope` | Copy every field to `CardScope`; no flattening to conversation/project alone |
| `ComponentSnapshot` | IDs/revisions/attempt to `CardBinding`; host supplies the correct digest context and trusted capabilities |
| `draft` / `committed` / original receipt | Distinct draft fields and verified save status; never infer saved from selection or local submit |
| `PendingSubmission.identity` | Exact `OriginalCardRequest` from scope+IDs+component/state revision+attempt/action/intent/paramsDigest |
| `PendingPhase.UNKNOWN/CANCEL_REQUESTED` | Unknown/pending display and original lookup only; terminal labels require verified terminal observation |
| `ActionProposal.OpenSource` | Source ID+revision+page through common source/document locator; enrich anchor/availability only from trusted source data |
| `ActionProposal.ComposeDraft` | Fill a local draft; never map directly to `SendDraft` |
| `TrustedHostReviewRequired` | Existing trusted preview path; no executable model-specified methods |
| attachments / evidence / versions | Existing contract has no structured payload schema for these; shell must supply trusted view projections, not extend model parser opportunistically |

This branch deliberately does not implement the bounded transport decoder, durable snapshot mapping, host business adapters, source reader, storage, preview authorization or ChatScreen/MainActivity wiring. In particular, PDF reading/annotations belong to the common capability layer for all businesses. These cards expose neutral source/document references only; there is no research-specific PDF engine or SDK selection.

## Verification and render entry points

Run the standalone Kotlin checks with an installed compiler (runner downloads nothing):

```sh
KOTLINC=/path/to/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh
```

`ActionCardsTest` supplies Compose behavior/semantics tests. `CardRenderingTest` supplies four real render/capture tests for light/dark and 100%/200% text at a 320dp surface, scrolling each card into view. On actual Android execution, captures are viewport PNGs under the target app external-files `card-rendering/` directory; they contain clearly labelled offline fixtures. They are not golden assertions or full-page screenshots. No PNG exists merely because these test sources exist.

With the existing approved product inputs, Gradle/SDK/emulator and native/model packaging available, the shell verifier can compile and run only these two test classes using the standard product test workflow. Example selector: `-Pandroid.testInstrumentationRunnerArguments.class=com.mightyoung.muyon.product.ui.cards.ActionCardsTest,com.mightyoung.muyon.product.ui.cards.CardRenderingTest` with `:app:connectedDebugAndroidTest`. The existing product native/model gates remain required; do not bypass them to manufacture acceptance.

Current execution results and independent review are in `docs/tasks/ui-action-cards-20261022/`. Android compile, lint, behavior tests, render capture, screenshot inspection, TalkBack and actual host integration are NOT_RUN here; this is not a production-ready or all-UI-complete claim.
