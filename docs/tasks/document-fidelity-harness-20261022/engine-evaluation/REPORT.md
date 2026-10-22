# DOC-05/07 installed-engine evaluation — execution HOLD

2026-10-22 UTC. Continues task/document-fidelity-harness-20261022 from bfdd7ecd7e8ec6a7825d959b6f8a5e8e7cf20ef8. User authorized installed-engine evaluation and explicitly required stopping engine execution if isolation was unavailable. This batch advances evidence/corpus; **no Office edit or round-trip was executed**.

## Isolation outcome and exact stopped action

Action: create a bubblewrap user/network/PID/IPC/UTS namespace running only `/usr/bin/true`, clear environment, read-only `/usr`, `/lib`, `/lib64`, private `/tmp`, proc/dev, die-with-parent/new-session. Tool: existing `/usr/bin/bwrap` 0.12.0. Outcome: failed exit1, `bwrap: setting up uid map: Read-only file system`. This is an environment filesystem denial while preparing UID mapping, not an automatic-approval-review rejection. Raw command/output retained in evidence/isolation-attempt.log as the original tool transcript; it was not re-executed to capture a log.

No retry, escalation, unshare alternative, relocation, policy change or weaker engine route. Host NoNewPrivs=1, Seccomp=2 and zero process capabilities are useful existing controls but do not prove a private network or restricted engine filesystem. Available prlimit/timeout do not by themselves prevent access to host files/network. No engine import/document load or soffice `--version`/headless call attempted. Existing wrapper can create a profile directory, so static files were used for version evidence. No EULA accepted, package installed, cost/credentials configured or remote file uploaded.

## Installed candidates and actual source evidence

Read-only `importlib.metadata` plus static files; actual installed versions, installation paths, project/homepage declarations, requirements, METADATA/RECORD/WHEEL/INSTALLER/license hashes and gaps are in evidence/installed-inventory.json. Project URLs are package declarations, not independently authenticated origins. INSTALLER says pip; direct_url descriptors absent in these distributions. Original wheel/index/download origins and signatures were not recovered or verified. No engine or dependency code was vendored.

| Existing candidate | Version from installed metadata | Locally observed license evidence | Status |
|---|---|---|---|
| python-docx | 1.2.0 | Full installed MIT text, copyright/notice condition | Candidate only; depends lxml/typing_extensions |
| python-pptx | 1.0.2 | Full installed MIT text | Candidate only; depends lxml/Pillow/XlsxWriter/typing_extensions |
| openpyxl | 3.1.5 | Full installed LICENCE.rst MIT text | Preferred future single-cell evaluation; no calculation claim |
| et_xmlfile | 2.0.0 | MIT LICENCE.rst **plus** LICENCE.python (Python-derived-code notices) | Preserve both; top-level MIT alone is incomplete inventory |
| lxml | 6.1.1 | BSD-3-Clause LICENSE.txt plus LICENSES.txt exceptions/resource-specific terms | Includes notices referencing ElementTree, test runner, schematron resources; bundled native/component audit incomplete |
| typing_extensions | 4.16.0 | Metadata expression PSF-2.0 and installed full license file hash | Exact artifact provenance and distribution review incomplete |
| Pillow | 12.3.0 | Metadata expression MIT-CMU and installed LICENSE + available SBOM | Native/component audit incomplete |
| XlsxWriter | 3.2.9 | Installed BSD-2-Clause text and metadata | Candidate transitive dependency only |
| soffice / LibreOffice native tree | Static ProductKey `LibreOfficeDev 26.8`, buildid `2c87e51eeaa2b413ff4ae097b2705eea1995d8e5` | Installed LICENSE says MPL2 plus component notices; 123 `##` headings inventoried, wrapper/native executable/license hashes retained | Dev/custom metadata (`Vendor=root`); exact upstream binary origin and complete component/font obligations unverified; no runtime version invocation |
| POI | No `*poi*.jar` found under `/usr/share/java` or runtime dependencies root | No artifact to inspect | Scoped absence only, not whole-machine assertion |

LICENSE-INVENTORY.md provides exact full-license-file SHA/path index; machine-readable inventory includes hashes for metadata, installer, wheel descriptors, RECORD and known native executables. These hashes identify the local snapshot, not signature verification or supply-chain approval. No commercial/unknown SDK selected. Local permissive license observations are not a blanket approval for redistributing a bundled engine or all transitive resources.

## New original corpus and predeclared operations

Added deterministic standard-library-only complex.docx and complex.xlsx in tools/document_fidelity/fixtures_complex; no old fixture changed. Manifest preserves source SHA and all ZIP members, bounded structure report and a **non-executable** operation contract (`execution_allowed=false`, round_trip/reopen/semantic/render/recalc all not_run).

- DOCX has original text split into three runs; only the bold middle run `target` would become `edited`. Bookmark/comment range/reference and header are linked. Only word/document.xml could differ; exactly one w:t text could change; all other nodes/attributes/run styles and every other member must remain invariant.
- XLSX has two sheets including hidden data, named range, date1904, date style/serial, merged title, precision sample, comment/VML and an opaque custom member. Planned operation is Original!A1 numeric value2→5, changing only A1/v in xl/worksheets/sheet1.xml. Formula B1 `A1+1` has deliberately stale authored cache999. Formula and cache remain unchanged in this no-recalc test; neither999 nor newly written formula would be reported as calculated. Hidden sheet/styles/comments/relationships/opaque bytes must be identical.
- Every source part except the single authorized XML member is byte-invariant, including custom/original.bin. Inside the allowed member, compare full parsed structure/attributes/text excluding only the specified value; no serialization changes to unrelated semantic nodes are authorized. Missing or rewritten opaque parts is failure, never an allowable library-normalization effect. Package metadata/container-byte differences would be reported separately.

Expected future trial, only in a qualified existing sandbox: source read-only and immutable; single approved engine/version and sanitized environment; no host credentials/profile, no network/macros/external refresh/embedded execution; resource/time/output limits; edit a fresh copy, preserve engine logs and candidate hash, independently reopen using a separately implemented standard-library XML/ZIP oracle, compare member bytes + allowed-node semantics, re-inspect safety, verify original hash unchanged. CLI exit0 only proves process return; no commit/revision/publish approval follows. Any unexpected member loss/rewrite fails the trial and candidate eligibility. No output candidate exists in this batch.

New source hashes:

- complex.docx `ce3bc59163545067a56307714b9422851c5fa8a9288f0e08e088fbe225d958fc`
- complex.xlsx `e1bbea112782f0350fbe348a2a021d8d0926ed8c2c768be528ef2fc9317ba78d`

## Verification and remaining gates

`python3 -m unittest discover -s tools/document_fidelity/tests -v`: PASS32 tests (27 prior +5 new); original scaffold RED with errors and corrected assertions-only RED5 failures retained. `python3 -m tools.document_fidelity.engine_inventory`: PASS metadata report only, does not probe/execute engines. `python3 -m tools.document_fidelity.complex_fixtures`: creates new corpus once via exclusive writes; source-byte/manifest reproduction checked for all six specimens in evidence/fixtures-check.log. Engine reopening, desktop opening, schema conformance, visual, semantic edit preservation and recalculation NOT_RUN. Prior missing-Flutter full-suite failure remains applicable; no dependency installation attempted to remove it.

Unresolved gates: enforceable network/filesystem/process isolation unavailable in this selected environment; exact installed artifact origins and complete native/transitive/font redistribution review incomplete; no approved editor/renderer/recalculator adapter; no actual round-trip/reopen/render/recalc result. Isolation failed on harmless true, before any document engine work. Existing built-in Python and process restrictions are not claimed equivalent. Parent may provide a separately authorized already-isolated environment; do not retry this denied namespace action without materially new relevant evidence. No permission expansion requested.

Scope: tools/document_fidelity new inventory/corpus/tests, plus this independent docs subtree. Existing harness and original fixtures unchanged. main/develop untouched; no merge/deployment/model/search/unknown-operation retry; Leader B retains develop integration. Independent review and exact new commits are recorded in REVIEW.md and continuation handoff once sealed.
