# DOC-02/05/07 offline foundation plan

Goal: original, standard-library-only bounded read-only OOXML inspection and conservative PDF preflight; no editor integration.
Base: task/ui-shell-20261022 @ 3ecb544ad0a47ccc38fe830777f35588b92e8afc; verified remote Android candidate f4781e16ddf4e542b983fbd77f266a0071148255.
Spec: delegated DOC02/05/07 request and Library libfile_c94323014d388191ba1853e9aef8f532 / libfile_f74abbd878e081918ff0e1886325a7fd (both full reads, has_more=false).

Only tools/document_fidelity/ and this independent docs directory are owned. No production/UI/Rust edits, dependency installations, real model/search calls, credential configuration, network document loading, main/develop changes or merge. Historical 2 unknown requests and ¥0.002620 reservation remain untouched.

- [x] Write real synthetic ZIP/XML/PDF fixtures and behavioral tests; run RED against unsupported scaffold.
- [x] Implement inspect(path) -> JSON-serializable dict and compare(original, candidate) -> dict in harness.py; command line emits JSON to stdout only. All input opens read-only, never extract archive.
- [x] Bound compressed size, archive metadata/count, expanded total/member/ratio before reads; reject unsafe paths, symlinks, duplicate names, encryption, malformed XML, entities and invalid package metadata. Cross-check extension, main part content type, root and officeDocument relation. Record macro/external/embedded features and reject unsafe processing. Unknown parts retained in hash manifest; structural PASS is only a limited package check.
- [x] Compare all original parts conservatively: any missing/changed bytes fail preservation, additions unknown. No semantic/visual/formula/comment claims. PDF byte-marker scan is incomplete; parse/render always NOT_RUN, no safe verdict.
- [x] Generate four original minimal fixtures, source hash/member manifests and sample reports. Add CLI tests, malformed/UTF-16 XML, internal traversal, resource bounds, unknown-part loss and immutable-original checks.
- [x] Run offline unittest suite, diff check and available repository verification; retain original logs including failures/NOT_RUN. Commit immutable implementation then request independent read-only review; fix findings with RED/GREEN and seal evidence. Push only task branch and verify remote SHA (publication receipt recorded separately after sealing).

Review focus: ambiguous package roots; encoded traversal and external relationships; forged/encrypted ZIP flags; XML encoding/entity bypass; PDF obfuscated actions and missing parser. Fail closed or report unknown, never certify safe documents.
