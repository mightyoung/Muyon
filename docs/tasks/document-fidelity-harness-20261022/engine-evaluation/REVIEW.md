# Independent review — installed-engine fallback continuation

Reviewed immutable `ff2eed64c74b070885d1fedaaae07adcfc7cf916` vs `bfdd7ecd7e8ec6a7825d959b6f8a5e8e7cf20ef8` in separate read-only review. Supplementally reviewed current resource/parser evidence and updated REPORT. Reviewer found no new issues in inventory/synthetic-corpus scope and recommends accepting that scope only. Actual engine execution remains HOLD.

Exact independent commands, from isolated immutable snapshot:

```sh
python3 -m unittest discover -s tools/document_fidelity/tests -v > independent-tests.log 2>&1
python3 -m tools.document_fidelity.engine_inventory > independent-inventory.json
python3 verify_review.py > independent-fixtures-and-inventory.log
```

Portable rerun from repository root:

```sh
PYTHONPATH=. python3 docs/tasks/document-fidelity-harness-20261022/engine-evaluation/evidence/independent-verify.py
```

Results: 32/32 tests passed. All six generated fixtures match committed bytes/manifests and remain unchanged after inspection; complex operations execution_allowed=false, all engine-dependent states not_run, unknown/opaque part invariants retained. Formula A1+1 and stale cache999 are original fixture data, no recalculation claim. Fresh metadata exactly equals recorded installed-inventory.json. Reviewer explicitly checked sys.modules for docx/pptx/openpyxl/lxml/PIL/xlsxwriter/et_xmlfile absence after inventory/corpus verification. No namespace/engine subprocess, retry/alternative, network, installation, repository write, commit or push by reviewer.

Raw independent logs, fresh JSON and verification source are retained in this directory's evidence/independent-*. Supplemental resource observations and optional parser source hash do not establish confinement, runtime parser choice or license approval. Current engine route is blocked by enforceable isolation, authenticated artifact origin and complete native/transitive/font licensing review. No attempt to bypass the known UID-map filesystem denial was made.
