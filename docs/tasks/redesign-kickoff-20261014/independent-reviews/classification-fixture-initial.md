# A00 classification fixture independent review — initial fixed artifact

Fixed source `fe5896f5edbf4400de2b885cf7d3791636a0d98d`, branch `task/leader-b-redesign-a00-classification-20261014`, parent/base `bc5b2c37a98bfa417c0f35f5383b76dfb03be85a`. Non-author reviewer, all reads from immutable git blobs; no author/product edits or classification runner. **I: two required input consistency corrections before C0 draft-material intake.**

## Required corrections

1. **I01 — F10.json:278.** Auto/high under `synthetic_frozen_assumption_for_routing_only` carries `mode_facts.extra_risk_confirmation_is_required=false`, while :300–304 expects current-intent confirmation and one risk confirmation. False is contradictory fixture input, not a product decision. Correct to true for this one Auto/high branch, retain FullAllow zero-risk-confirmation semantics and all not_run status; preserve original commit and refresh hash manifest.
2. **I02 — A01.json:44,70,95–115.** Required/actual unit is page.2 and attachment rule covers pages.1–7, but credential/purpose rules only cover unit.synthetic.1 and source unit/check target has no binding to page.2. Eligible expected result lacks a coherent actual-page check relationship. Bind page.2 to the actual normalized checked content and both prerequisite coverage sets, or explicitly define a verifiable alias. A02 should similarly name the parsed-page/required-page relationship while continuing to reject the full 10-page task with pages 8–10 unavailable. No new rule/case or product behavior decision needed.

Root notified immediately and authorized the author’s narrow delta. This review does not modify the author branch.

## Actual static checks

Passed: exactly 34 new reserved files, no source/schema/tests/config edits; original A00 set of 29 V131-T02 IDs exact; 77 unique local variants; all 14 rule IDs proposed_unfrozen; case/variant fields and referenced rules; case statuses not_run, captured payload absent, database results not observed; original 52 main cases unchanged/not_run; six immutable source input SHA256s; reviewed D01a contract byte equality with 99c4d779bb5b94e3388637228f42869d6e81152d; 32 fixture SHA256SUMS entries; local links; diff check. Machine evidence: classification-proof-fe5896f5.json outside Git. Structural success is not 29 or 77 product passes.

## Semantic review and future evidence limits

The 11 F cases preserve trusted field declaration AND normalized actual generated new value check, source version and restrictions, stale-evidence invalidation, unknown-field rejection, no-coverage terminal attempt, adopted/edited model lineage, separate mode/risk and CAS/idempotency gates. F07 retains commercial source despite target none. F08 explicitly has no model/outbound eligibility under local-only minimal coverage; FullAllow missing only AutoRule remains eligible, whereas missing actual ValueCheck stops. Unknown sources stop without treating every local payload as prohibited. FullAllow classification/content evidence is not a grant.

Original U/A/P/D/M/F/C/N scenarios remain traceable. Symbolic credential sentinel is metadata, not a real detector test or leak canary; clipping preserves version relationships and retention limits; no_coverage cannot become classified through time, mode switch, confirmation or model label; genuine new content/rule creates a new attempt while retaining old failure. No product DTO, classifier, mirror algorithm, Rust implementation, new Sensitivity, real model, Android or external transmission introduced.

**Scope clarification for future runner:** F01 local variant and several other cases set multiple `*_body_allowed` flags true despite only one current purpose. README explicitly limits body allowance to the stated scenario/purpose, and action_result/prerequisites remain separate. These booleans can only describe candidate content eligibility for the selected current purpose; noncurrent-purpose flags do not prove coverage or outbound permission. Future format should represent only current-purpose content eligibility, or label other-purpose flags not_applicable. Do not interpret local eligibility as outbound authorization, blocked risk as content unclassified, or false in an outbound negative as a global local-write ban. F08 already explicitly sets model/outbound false for globally uncovered local input. This is draft-input interpretation, not a new product restriction or completed M03 schema.

M03 runtime mapping, actual current-purpose rule registry/detector coverage and false-positive/negative bounds, payload capture, trusted source/permission/receipt/DB observations, normalization equivalence, actual Android load and recovery proof remain missing by design. C0 after correction would cover fixture-material intake only.
