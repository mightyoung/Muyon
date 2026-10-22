# Independent source review and single verified fix pass

Fresh independent reviewer reviewed82f630553dc816f079cc30b33b156cebdcea26db against77a000bcb59dd5de3e40887f03fb612622c09e9e, ran57 tests successfully, checked8 deterministic fixtures/full manifests and previous6 plus both manifests byte-equal base. Review performed pure stdlib/fake probes only, no third-party import/execution/worker CLI/namespace retry/network/install/repo write. Full report transcript retained as evidence/independent-review-transcript.txt; independent probe source retained unchanged. Reviewer supplied no raw suite-file artifact, so no authored replay is mislabelled an independent log.

Three P2 source screening gaps:

| Finding | Original independent probe | Fix + regression |
|---|---|---|
| Duplicate XLSX sheetFormatPr ignored | second declaration defaultRowHeight0 invisible to preview; supported/fake dispatch | Reject duplicate visibility-related singleton declarations and duplicate/invalid row ids; ambiguity regression also covers duplicate hidden row declaration |
| DOCX non-target w:t not enforced as leaf | nested b node inside adjacent w:t accepted | Validate every w:t/style leaf and xml:space value across source, not just selected run |
| PPTX presentation-size children/attrs not screened | nested timing in sldSz accepted | Enforce empty exact cx/cy size nodes, bounded positive sizes; regression also covers unknown attrs and nested notesSz |

Single author fix pass:3 new regression methods failed6 subcases before changes, then60/60 full suite passed. Re-running original independent probes by author now yields all3 preview unsupported/rejected, zero fake calls, real status held. Original false-acceptance replay preserved before fixes in author-original-review-probes.log; fixed replay in author-fixed-review-probes.log. Both are author replays of independent probes, not independent post-fix verification. No second independent60-test run claimed.

No known independently found issue remains unfixed. New conservative restrictions may reject valid complex documents; that is the intended boundary, not full Office capability. Real engine/process sandbox/qualification and reader/render/annotation/CAS/UI integration remain NOT_RUN/HOLD. Numeric lexical serialization5.0→5 remains untested real-library compatibility and an oracle failure; no relaxation made.

Commands from repo root:

```sh
python3 -m unittest discover -s tools/document_fidelity/tests -v
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python3 docs/tasks/document-fidelity-harness-20261022/text-subsets/evidence/independent-probes.py
```
