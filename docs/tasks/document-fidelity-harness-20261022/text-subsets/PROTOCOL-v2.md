# Proposed neutral txn protocol v2 and v1 migration

Same owner boundary: Rust document_edit host owns scope/authorization/immutable source handle, revision, idempotency, durable candidate/report storage, cancellation and CAS/commit receipts. Python owns adapters/oracles only. No Rust/Android schema or source changed; actual host mapping is NOT_RUN. No request provides paths/URLs/commands/grants or engine binaries. Real entry and worker CLIs remain unconditionally HOLD. No software/library execution or isolation retry is authorized by a preview/fake verdict.

## Wire versions and tightened XLSX policy

Schema1 envelope and set_numeric_cell operation fields remain unchanged; existing positive XLSX example is accepted. **Policy tightening:** hidden sheet/row/column, effective workbook/sheet protection, merged targets, malformed/ambiguous visibility/dimensions and non-numeric/formula targets are unsupported before fake dispatch. This supersedes adapter-source/HOST-PROTOCOL's older worksheet-only visibility ruling; legacy callers must re-preview and handle rejection. Wire compatibility does not retain unsafe old eligibility. Preview exposes source flags plus literal old/new values, never claims a visible UI selection or rendered visibility.

Schema2 retains exactly the same envelope keys (schema_version, scope_id, file_id, base_revision, operation_id, idempotency_key, source_sha256). Numeric operation may use1 or2. New tagged operations require2; v1 text, unknown tags/fields or unrecognized versions reject. A v1-only host must reject2 until explicitly mapped, never silently coerce or omit locator/hash fields. Host request digest/idempotency must bind complete version/envelope/operation and distinguish mismatched reuse. No actual Rust/CAS compatibility is asserted by this proposal.

## DOCX operation

replace_docx_run_text fields: kind, part=`word/document.xml`, paragraph_index, run_index (both zero-based direct body-p/run positions), target_sha256, expected, replacement. Part+structure path+local hash+exact expected text are revision-bound through source SHA/base_revision. No cross-run text replacement or search/guess fallback.

Supported source is plain direct body paragraphs/runs, exactly one w:t per run, optional simple bold/italic rPr, optional final empty sectPr. Reject Word auxiliary parts (headers/comments/footnotes/styles/etc), tables/columns/sections/fields/revisions/hyperlinks/bookmarks/drawings/special containers/unknown tags or attributes. Existing richer DOCX corpus is intentionally unsupported. Require exact text and local hash; reject replacement needing xml:space changes or newline/tab/control/XML-invalid input. Other runs, styles, whitespace, comments/PIs and all non-target parts remain invariant. This is a tiny source/fixture subset, not Word layout/read/edit compatibility acceptance.

## PPTX operation

replace_pptx_shape_text fields: kind, part (resolved ppt/slides/slideN.xml), slide_id, shape_id, paragraph_index=0, run_index=0, target_sha256, expected, replacement. Resolve stable source slideId through presentation relationship Type=slide; require part agreement, unique cNvPr ids and selected shape id. No slide filename guessing or text matching across shapes.

Supported source is one-slide, one ordinary rectangular text shape, one paragraph/run/text node, bounded positive on-slide geometry, simple optional run font flags. Direct-child grammar is checked. Reject additional slide/auxiliary master/theme/layout/notes parts or relations, placeholder/group/table/chart/picture/field/media objects, animation/transition, rotated/flipped/out-of-bounds geometry, non-default body layout, multi-run/paragraph text, hidden shapes and unknown namespaces/attributes/containers. No styles/theme normalization fallback. New synthetic fixture has no master/layout/theme and has not been opened by a real application or engine. Normal production decks will often be unsupported; that is deliberate.

## Local fingerprint and output oracle

`target_sha256` hashes the source **run** subtree, not arbitrary rendered/text content. Algorithm expanded-tree-json-v1: recursively `[expanded_tag, sorted [[expanded_attribute,value],...], text_or_null, tail_or_null, [child_forms...]]`; comment/PI tags encoded `#comment`/`#pi`; serialize via JSON ensure_ascii=true, separators=(',',':'), no trailing newline; SHA256 UTF8 bytes. See text_common.local_fingerprint. A future host must implement/compare the same canonical form or call authorized read-side metadata; changing algorithm requires an explicit protocol revision. Source SHA binds all namespace/context/package bytes. A hash is a precondition, never authorization.

Oracle always reopens/preflights candidate with matching true format and extension, requires exact part set, and compares every non-target part byte-for-byte including unknown/opaque parts. Target part must equal expected entire XML tree except the single designated text node; expanded attributes/tags, neighbor text, style nodes, comments/PIs and prolog/epilog positions remain invariant. Unsupported library serialization/unknown-part loss fails, never treated as a benign normalization. Numeric output5.0 vs5 remains a strict mismatch; no measured compatibility claim exists.

Response echoes request schema/identity after parsing; preview is supported/unsupported metadata, candidate verification pass/fail, engine_execution/real_roundtrip/render/recalc/visual/annotation not_run and safety/fidelity unknown. Accepted fake results remain simulated_validated plus fake_executor_used=true. No real process launcher, attestation/cancellation or publication is implemented; fake callbacks are trusted test code with post-return limits, not isolated executable workloads. Rust alone can create a durable candidate and subsequently CAS after independently rechecking authorization/source/revision; Python never emits committed/saved/synced.

## Four-format remaining work

- XLSX: source preview and numeric-copy oracle/fake pipeline only. Real openpyxl round-trip, cache/recalc behavior, layouts/charts/tables/advanced formulas, renderer and product reader integration remain NOT_RUN.
- DOCX: narrow run source/preview/oracle and dormant python-docx only. Real reopen/render/edit, complex layout, anchors across revisions, comments/revisions/annotation round-trip and product reader remain NOT_RUN/unsupported.
- PPTX: narrow synthetic single-shape source/preview/oracle and dormant python-pptx only. Real engine/application opening, masters/themes, multi-slide/shape editing, overflow/fonts/visual comparison and reader/annotations remain NOT_RUN/unsupported.
- PDF: existing conservative static preflight only. Reserve a future sidecar/annotation boundary keyed by scope/file/revision/source hash plus page/box/rotation/text anchor; sidecar storage/export must be explicit and separately authorized. No PDF content-edit or annotation schema/engine implemented here, no string patching, parser/render and signature/annotation verification NOT_RUN.

All engine/license/provenance/isolation/runtime and UI/CAS acceptance gates remain. The historical bwrap UID-map filesystem denial is never retried or bypassed by this source-only slice.
