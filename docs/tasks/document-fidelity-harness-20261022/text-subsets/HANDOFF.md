# Parent / Rust host author / Leader B handoff

Same branch task/document-fidelity-harness-20261022; base77a000bcb59dd5de3e40887f03fb612622c09e9e.

New source commits:

- 82f630553dc816f079cc30b33b156cebdcea26db — XLSX hidden/protection/merge preview gate; explicit schema2 DOCX/PPTX text union; part/path/local-hash/expected locators; small-layout grammar; independent oracle reuse; dormant workers and original2 fixtures; independently reviewed.
- b3574ae3d4e69a9e60e9c4c6fb34388f11451251 — single review-fix pass for duplicate visibility declarations/rows, all DOCX text/style leaves and full PPTX size-node grammar. Author60 tests and original independent-probe replay pass. No independent60-test rerun claimed.
- Final sealing commit is evidence/handoff/ledger only; final remote full SHA returned by execution response after push/readback.

Deliverables: PROTOCOL-v2.md (v1 numeric wire retained; hidden-row/column behavior explicitly tightened; v2 text not coercible to1), REQUESTS-v2.json, REPORT/REVIEW and raw evidence; tools/document_fidelity/adapters and fixtures_subsets/manifest. Current policy supersedes previous worksheet-only visibility ruling: hidden/unknown sheet,row,column, protection or merge unsupported before dispatch.5.0→5 candidate differences still fail; real serialization compatibility NOT_RUN.

DOCX: direct plain body-p/run/one-t, simple bold/italic only; reject rich Word auxiliary parts/fields/revisions/hyperlinks/tables/columns etc and xml:space-changing/newline/tab inputs. PPTX: one synthetic slide/plain rectangle/paragraph/run only; stable slide-rel/unique shape id, small complete grammar, no placeholder/table/chart/master/theme/animation/rotation/complex text. Non-target parts exact bytes incl unknowns; target tree unchanged except one text. Normal real documents may be unsupported. Synthetic source/fake success does not establish actual engine/application opening, layout/edit/recalc compatibility.

Validation: final author unittest60/60; initial independent57 tests and8 fixture/manifest/base checks; all3 independently found P2 issues fixed by RED→GREEN plus author replay of original probes (unsupported/rejected,0 calls,HOLD). Source fixtures8 deterministic, prior6/2 manifests unchanged. Raw failures, syntax-edit error, RED log whitespace/raw diff exit2 preserved. Scoped source/docs checks pass. No engine/worker CLI/namespace retry; fake callback tests only, no hard process timeout guarantee.

Rust owner continues to own scope/revision/read handles/auth/idempotency/durable blob/report/CAS/commit receipts. Protocol is a proposal, not wired into in-progress gateway, and no Rust/Android files touched. Real runtime and all3 worker entries always raise/HOLD before third-party import. Missing sandbox/launcher/artifact/license/native/font qualification, true reopen/render/recalc/annotation/public readers and host/UI integration remain open. PDF only conservative preflight; future sidecar annotation boundary reserved, no PDF string patching or content editor. All4-format overall completion explicitly NOT claimed.

No installation/EULA/payment/credentials/security configuration/permission expansion, real user document, model/search/network transfer, bwrap retry/unshare bypass, deploy/main/develop merge/force push/delete. Historical2 unknown/¥0.002620 untouched. Leader B alone merges develop; parent may consume exact source commits after its own review.
