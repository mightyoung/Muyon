# Adapter source execution ledger

Spec: delegated minimum openpyxl-candidate single-cell adapter/protocol, test fake executor only, keep real engine HOLD, no Rust/Android edits. Base7037166d4f1154ebbb38bdaea158b6ac4f8b544a. Existing isolation denial never retried.

Ruling: no real subprocess executor or injectable production launch escape hatch in this checkpoint; run_real and worker main hard-HOLD. Source entry contains gated openpyxl edit implementation for future integration; no import unless gate changes in a separately reviewed future patch. Cost: runtime integration remains NOT_RUN; avoids caller-asserted flags bypassing known isolation failure.

- [x] Define neutral HOST-PROTOCOL and inert fixed launch spec; ownership above.
- [x] TDD strict request schema, identity/hash/precondition, one existing numeric cell, safe preflight and selected worksheet part resolution. Reject formula/hidden/protected/merged targets.
- [x] TDD fake executor orchestrator: private read-only source snapshot/output copy, fixed argv/limits, bounded regular output, source hash, exit/timeout/output limits/sidefiles/errors, no production publication; simulation labels cannot become real receipts.
- [x] TDD independent XML oracle: exact part set; every non-target byte invariant including unknown parts; exact expected one-node delta in target part (preserve comments/PIs), stale cache and all other semantic nodes unchanged. No engine/render/recalc validation claims.
- [x] Implement disabled worker source, no engine import/launch in tests; verify all tests, fake negative cases and immutable original fixtures. Independent review, raw RED/GREEN logs, task-only commit/push/full SHA handoff.

Interfaces: protocol.parse_request(dict)->validated dict; xlsx.prepare(source_bytes,request)->plan (resolved target part, source manifest, expected XML); xlsx.validate_candidate(plan,candidate_bytes)->report; runtime.build_launch_spec(request)->inert dict; runtime.run_real(...)->held report; runtime.simulate_for_tests(source_bytes,request,fake_executor)->simulation report. No host-path or production grant entry in request. No public CAS implementation here.

Final review rulings: P3 malformed admission was re-graded as protocol correctness requiring a stable held response (otherwise host integration can crash); fixed in same review-fix pass. Hidden row/column acceptance is retained for explicitly addressed cells: the documented visibility restriction is worksheet-state only, not a visible-selection UI contract; cost is that future host must disclose/restrict hidden targets before enabling execution. Current real HOLD prevents live edits. No deferred minor finding remains.

Review-fix pass: outside-root PI/comment prolog/inside/epilog position now preserved; malformed diagnostic policy types return held. Both regression tests RED then GREEN; full suite43/43; independently authored original probes rerun by author now reject moved PI/hold malformed admission. No second independent rerun is claimed.

Final source checkpoint d18636f7f1eb7a54f06b647eae14aa55d0da89d1; final-author-suite.log43/43, author-fixed-probe-assertions PASS. Publication receipt verified by final execution command; no merge requested or performed.
