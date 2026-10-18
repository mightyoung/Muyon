# CTX-EXP-01: isolated evidence projection mechanics

2026-10-18. Candidate experiment only. The user's latest condition is that the
three proposed changes must prove useful experimentally before implementation.
No source in this crate is linked to the product, core-agent-lab, a host, a plugin
or a default feature. No production implementation or admission decision follows
from passing these tests. No neural backend is implemented.

## Frozen question and limits

Can a bounded, deterministic **synthetic** evidence projection preserve unknown
and exact source identity while rejecting changed, unavailable or ineligible
sources, without treating narrative claims as receipts or grants?

This is an invariant/protocol experiment, not a model effectiveness experiment.
Inputs called current sources and policies are explicitly trusted test fixtures.
Their presence does not prove provenance, a production receipt lookup, current
classification, host authorization, durable state, or revocation propagation.
The `Source` struct is local to this crate and is not a proposed public schema.
No raw message/tool body is loaded. Only synthetic ASCII references are used.
The `claim` input is adversarial synthetic narrative and never emitted.

The fixture uses the same source snapshot on both sides except for one named
mutation. Versions are compared only for exact equality with scope/store/stream,
invocation, receipt and outcome. No ordering between distinct version domains is
defined. Unknown cannot turn into failed-no-effect or success through a claim.
Known synthetic outcomes require a receipt reference; a reference's existence
alone still does not prove a real receipt or a verified business claim.

## Predeclared protocol, baselines and controls

1. Record source SHA, Rust version, fixture SHA256 and command exit status.
2. Run the same 17 fixed cases and four adversarial narrative claims. The first
   behavioral RED uses an intentionally incomplete `project` stub, which returns
   `not_implemented`; the reachable assertion must be
   `UNKNOWN_SOURCE_NOT_PRESERVED`. Build/import failures do not count as RED.
3. Implement the local candidate only after that RED. Re-run the full crate suite.
4. Valid unchanged raw metadata is the ground-truth baseline for the two permitted
   cases (unknown and synthetic receipted success). Candidate output must preserve
   that metadata exactly. This baseline is an oracle, not an alternative LLM.
5. Budget is UTF-8 bytes, **not tokens**. Charge the entire serialized metadata
   frame; exactly-fitting output is permitted; one byte less pauses. No partial
   frame or stale fallback. No token or cost savings are claimed.
6. Negative controls: missing implementation must fail the unknown check; accepting
   every source must fail negative fixtures; copying the narrative must fail the
   claim checks; silent truncation must fail the budget boundary test. Mutation
   checks will be reported individually if run.

Metrics are exact mismatch counts: unknown altered, ineligible source accepted,
eligible source lost, metadata changed, history mutated, narrative/grant copied,
or budget exceeded. Required counts are all zero. Every fixture's expected result
is frozen in `fixtures/protocol.tsv`. A blocked view contains no payload. No
action execution API exists. Absence of an action API is a scope constraint and
must not be presented as a tested production authorization boundary.

Stop this candidate on any mismatch. Stop promotion regardless of this result:
real model utility, source access integration, classification and policy wiring,
transaction/recovery semantics and UI remain untested. Protocol GREEN permits
only further isolated experiments.

## Future efficacy comparison: NOT_RUN, production blocked

Before any model trial, freeze the existing-summary implementation SHA and
behavior, datasets with permission/retention scope, fixture digest, model and
tokenizer revisions, sampling and repeated-run count, tools, input token budget,
trigger policy, total cost cap, and evaluation rubric. No model/network/paid run
is authorized by this experiment.

Use four arms on the same full trajectories: existing summary, longer summary
under the same input budget, summary plus exact retrieval, and summary plus
structured supplemental records. Include full history when it fits. The current
core's uncompressed raw-history admission behavior is a baseline observation,
not equivalent to the old Dart four-field summary. Do not fabricate a weak
summary control or call injected text an LLM result.

The model efficacy preregistration must separately report task success, invalid
repeat calls (excluding legitimate polling/changed state), stale decisions,
unknown misreported as success, evidence checkability, actual input/output and
total tokens, compression/recovery latency and end-to-end latency. Same input
budget does not imply same cost. Confidence intervals/repeated runs and the
minimum useful improvement must be fixed before results are seen. Without a
stable advantage over summary/retrieval, retain the simpler baseline. Any
unauthorized action, duplicate side effect, forgotten-source revival, or lost new
decision stops promotion immediately. Neuro/soft memory needs a separate later
proposal, exact compatibility contract and resource authorization.

## Reproduction

Use a pre-existing Rust toolchain; no external crates or downloads are needed:

```sh
cargo test --offline --manifest-path experiments/redesign/context-memory-lab/Cargo.toml -- --nocapture
```

Keep build output and raw logs outside Git. The task record records actual
commands/results and the exact implementation SHA; this specification does not
claim execution.
