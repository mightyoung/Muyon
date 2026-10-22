# Adapter source execution ledger

Spec: delegated minimum openpyxl-candidate single-cell adapter/protocol, test fake executor only, keep real engine HOLD, no Rust/Android edits. Base7037166d4f1154ebbb38bdaea158b6ac4f8b544a. Existing isolation denial never retried.

Ruling: no real subprocess executor or injectable production launch escape hatch in this checkpoint; run_real and worker main hard-HOLD. Source entry contains gated openpyxl edit implementation for future integration; no import unless gate changes in a separately reviewed future patch. Cost: runtime integration remains NOT_RUN; avoids caller-asserted flags bypassing known isolation failure.

- [ ] Define neutral HOST-PROTOCOL and inert fixed launch spec; ownership above.
- [ ] TDD strict request schema, identity/hash/precondition, one existing numeric cell, safe preflight and selected worksheet part resolution. Reject formula/hidden/protected/merged targets.
- [ ] TDD fake executor orchestrator: private read-only source snapshot/output copy, fixed argv/limits, bounded regular output, source hash, exit/timeout/output limits/sidefiles/errors, no production publication; simulation labels cannot become real receipts.
- [ ] TDD independent XML oracle: exact part set; every non-target byte invariant including unknown parts; exact expected one-node delta in target part (preserve comments/PIs), stale cache and all other semantic nodes unchanged. No engine/render/recalc validation claims.
- [ ] Implement disabled worker source, no engine import/launch in tests; verify all tests, fake negative cases and immutable original fixtures. Independent review, raw RED/GREEN logs, task-only commit/push/full SHA handoff.

Interfaces: protocol.parse_request(dict)->validated dict; xlsx.prepare(source_bytes,request)->plan (resolved target part, source manifest, expected XML); xlsx.validate_candidate(plan,candidate_bytes)->report; runtime.build_launch_spec(request)->inert dict; runtime.run_real(...)->held report; runtime.simulate_for_tests(source_bytes,request,fake_executor)->simulation report. No host-path or production grant entry in request. No public CAS implementation here.
