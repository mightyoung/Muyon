# Independent adapter source review and verified fix pass

Independent reviewer: separate fresh-context adapter_independent_review agent. Immutable source reviewed d023a616eaa7cf787be4041a939df08f53254c01 against7037166d4f1154ebbb38bdaea158b6ac4f8b544a. Reviewer ran41 tests successfully, checked six original fixture hashes/manifests/base bytes, and probed protection/namespaces/XML/ZIP/size, diagnostic policy types and XML special nodes. No engine import or execution, namespace retry/alternative, network, installation or repository write occurred in review.

Findings:

- P2 xlsx.tree originally recorded outside-root comment/PI type/text/order but lost prolog/epilog placement. Moving an xml-stylesheet PI across the root plus authorized numeric delta was accepted, violating documented invariants.
- P3 runtime.run_real diagnostic admission True/1/string/list raised AttributeError before returning held. It never executed an engine; author treats stable held responses as required protocol correctness and fixed this in the same pass.
- Observation: visible worksheet state does not exclude explicitly addressed cells in hidden rows/columns. This scope remains explicit in HOST-PROTOCOL; no UI visible-selection binding claimed. Future host must disclose/restrict hidden targets before runtime enablement. No unresolved defect classification for this observation.

Fix pass by author: two regression methods first failed (moved PI/comment false acceptance and malformed admission exceptions), then code records prolog/inside/epilog and validates mapping type; full suite43/43 green. Original independently authored probe script rerun by author confirms moved PI fails, malformed admission always held, six originals unchanged and engine_imported=false. No second independent review/43-test independent rerun claimed. No known found issue is left unfixed; real runtime/host integration remains HOLD/NOT_RUN by design.

Raw files: evidence/independent-original-suite.log, independent-original-probes.{json,log}, independent-original-false-acceptance.log; evidence/independent-fix-red.log, independent-fix-green-43.log, author-fixed-independent-probes.{json,log}, author-fixed-probe-assertions.log. The independent probe script retains original /workspace/document-fidelity and /tmp paths for exact reproduction in this environment, runs only stdlib/synthetic data plus local git show. It writes its report/reconstructed specimens under /tmp, never invokes an engine.

Commands:

```sh
python3 -m unittest discover -s tools/document_fidelity/tests -v
python3 docs/tasks/document-fidelity-harness-20261022/adapter-source/evidence/independent-probes.py
```

A test fake callback is trusted local test code; the simulator is not a sandbox and cannot forcibly cancel that Python callback. Fixed launch argv, OS limits, isolation/artifact attestation and Rust/CAS mapping are requirements for future integration, not implemented production guarantees. Fake validation is never evidence of openpyxl behavior, actual round-trip, visual fidelity or recalculation.
