# Bounded memory experiments — 2026-10-18

Status: **benefit UNVERIFIED**. Deliverables are a prospective experiment protocol and public synthetic contract fixtures. No model execution, paid calls, training, weights, GPU work, MemHub installation, private data, production writer, or production diff index is authorized or performed here. Fixture consistency is not host correctness, retrieval effectiveness, or model effectiveness.

The working source snapshot inspected for this plan is `a3ee7df596b0375aa9f3e6ff4c7651efd5f778a0`. The independent REMORY decision reference is immutable `34e388ee0c440ed191002067d7894c690a15610b:docs/design/agent-context-memory-20261017.md`. Its three candidates remain T (structured supplementary information), P (transaction compression), N (neural soft-token), each requiring demonstrated effectiveness before implementation. This plan neither implements nor admits those candidates. RSI remains **do not add**; this work does not reopen that decision.

## 1. Evidence and present boundaries

[DreamService](../../apps/muyon/lib/assistant/dream/dream_service.dart) already has offline proposal generation, optional explicit-profile model assistance, and separate acceptance. Its model prompt forbids tool selection/approval and conflict resolution; accepted summaries remain unverified with lineage. This is a comparator source, not evidence of a dedicated writer's benefit or proof of the proposed Rust host checks. The existing estimated token accounting is not a measured invoice.

[AgentEventSink](../../apps/muyon/lib/assistant/agent_event_sink.dart) describes append-only task events with repository-owned sequence numbers, digests, sizes, IDs and fixed codes, excluding model/request/response bodies. Git objects and existing event references are the diff baseline. Their availability, provenance and exact coverage must be measured, not assumed. No existing production semantic diff index was established in this bounded inspection. Synthetic `revision-synthetic-*` and `event-synthetic-*` identifiers below are illustrative, not real Git OIDs or newly assigned production IDs.

The fixtures contain expected outcomes for a future implementation to consume. The Python validator checks their internal consistency and coverage against these labels. It does not run either comparator, generate proposals, score retrieval, reconstruct patches, commit memory, or prove an implementation obeys the labels.

## 2. Dedicated memory writer A/B

Hypothesis W: separating proposal generation into a dedicated writer improves supported memory correctness and subsequent retrieval enough to justify its end-to-end cost. This hypothesis is UNVERIFIED.

Arm A uses the pinned existing offline/model-assisted DreamService extraction/organization behavior and its existing proposal contract. Arm B uses a dedicated proposal-only writer with the same authorized source projection, source order, token budget, schema, host admission rules, query workload and downstream retrieval. A future harness must adapt both outputs to the same evaluation contract, logging adapter failures rather than silently discarding them. Evaluate offline A separately: do not merge its zero-call cost with model-assisted A. First compare role separation using the same explicitly pinned model/profile and decoding settings; a cheaper writer profile is a separate preregistered comparison, not a confounded improvement claim. No training is part of either experiment.

The writer emits bounded candidates with intent/object identity, expected object revision, exact source refs and digests, lineage, content and candidate status. It cannot emit grants, mark an item verified, execute tools, modify policy, choose a commit target outside the host projection, or write storage. The Rust host alone validates schema/size, same-scope authority and its current revision, current policy generation, source rights and exact revisions/digests, complete lineage and tombstones, then checks CAS and commits transactionally with an intent-bound durable receipt. All checks must remain current at commit. Sources and model text are untrusted data. Read/model/write/outbound controls remain separate; the writer does not turn disabled automatic writing into manual approval work.

A change after queueing (manual edit, policy closure, authority/source revocation, forgetting) invalidates the old candidate. Reopening policy cannot revive its old intent. A replay with the same intent and payload resolves the durable receipt without another write; a changed payload is a replay conflict. Lost acknowledgement requires read-only receipt lookup, never blind resubmission. Missing rights/source/lineage/receipt means UNKNOWN and no commit. No version comparison across object, policy, authority or forgetting domains is permitted. Host acceptance of a candidate does not establish its factual correctness or make it verified.

### Prospective scoring and gates

Freeze the harness/source revision, all model/profile versions, prompts, adapters, cost schedule, corpus hashes, labels and seeds before any future output is inspected. Use 200 synthetic source histories (40 development, 160 sealed held-out), balanced across supported stable facts, corrections, conflicts, abstentions, revocations and forgetting; each has two fixed queries and exact supporting evidence. Score the same held-out histories/queries in paired arms; randomize arm presentation to two independent blinded reviewers, adjudicate disagreement, and retain all failures/timeouts. Current 20 writer fixtures are contract examples, not this effectiveness corpus.

| Measure | Definition | Gate to propose a separately authorized next stage |
|---|---|---|
| Host safety | Unauthorized/stale/tombstoned/verified-escalation commits, duplicate effects, receipt-conflict bypass | Zero across every adversarial case in both arms; one violation stops the run |
| Supported precision | Fully supported candidate facts / all nonempty candidate facts; abstentions reported separately | B >= 95%, and paired 95% CI lower bound for B−A >= −2 percentage points |
| Recall | Gold eligible facts represented by supported candidates / all gold eligible facts | B >= A−2 percentage points; no treating withheld/forgotten facts as eligible |
| Retrieval | Source-correct answerable-query recall@5; answers must cite exact eligible source revision | B−A >= 5 percentage points and paired 95% CI lower bound > 0 |
| Cost | Total extraction + admission + indexing + subsequent-query input/output tokens and priced cost per history; retries/failures included | B <= A on priced cost and measured total tokens; report offline A separately |
| Latency | End-to-end p50/p95 including host checks and retries | B p95 <= 1.20 × A p95 |

Use a paired history-level bootstrap (10,000 draws, fixed seed 20261018), keeping both queries and all candidate facts from a history together. Precision and recall denominators, confidence intervals and reviewer disagreement must be published with counts; an undefined denominator is UNKNOWN, never a passing zero. The small corpus supports only this bounded synthetic workload. Do not claim general user or coding benefit from it. No optional stopping, cherry-picked query removal, post-output threshold changes or selective retry exclusion. If a gate fails or confidence is insufficient, keep B experimental and report fail/inconclusive. Even all gates passing permits review of evidence; it does not authorize production integration.

## 3. Coding diff indexing A/B

Hypothesis D: a disposable sidecar over exact Git/event references improves historical diff retrieval compared with existing Git/event lookup without weakening source fidelity. This hypothesis is UNVERIFIED.

Arm A queries existing Git objects and authorized immutable event refs directly. Arm B queries a proposed disposable sidecar referring to those same objects/events. Both use the same query set, visibility/retention policy, exact snapshot and resource limits. Sidecar records are derived hints; Git/event facts and the Rust host remain authoritative. If A lacks an eligible source, mark its measured result UNKNOWN; do not invent an index or score unavailable history as an empty match. Do not replace A with a deliberately weaker text-search straw baseline.

Patch identity must bind repository identity, immutable source event ID, base and target content revision plus their exact digests, and patch digest. A Git commit alone can identify a version but may not identify an uncommitted action; preserve the host's immutable event identity. Existing qualified `(task ID, sequence)` may be an event handle only where the repository's immutability contract proves it. Literal patch text, session text, timestamps, filenames, text similarity and model summaries are never patch identity. Equal text in distinct events stays distinct. Rename/path metadata is tied to the exact event and versions. Never reuse a stale sidecar hit against latest file content.

At ingestion and query, check rights, source membership, current policy, tombstones and exact object integrity. Same event ID + identical frozen payload is idempotent; same event ID + different revision, digest or payload is **replay conflict / UNKNOWN**, not last-writer-wins. Missing base, missing target, corrupt patch/object/index, digest fork, stale coverage/generation and incomplete event history are **UNKNOWN**, not EMPTY. EMPTY is reserved for a complete authorized exact search with no match. Rebuild may read authorized original facts; it cannot recreate missing evidence or bypass forgetting. Do not execute a patch to decide identity or store raw patch/session bodies in the task-event table.

### Prospective scoring and gates

Before future prototype output, freeze 200 synthetic repository histories (40 development, 160 sealed held-out), three queries each, exact Git object and event manifests, and gold exact event IDs. Include repeated literal diffs across sessions/events, uncommitted changes, intervening edits, renamed paths, rejected events, duplicate/conflicting replay, missing bases and corruption. The present 16 diff fixtures are contract examples only. No production sidecar is implemented by this plan.

| Measure | Definition | Gate |
|---|---|---|
| Identity/integrity | Wrong event/revision/digest returned as source-correct; unauthorized hit; UNKNOWN collapsed to EMPTY | Zero; any occurrence stops run |
| Retrieval | Exact eligible event recall@5 and precision@5 on answerable queries; UNKNOWN/EMPTY coverage separately | B recall gain >= 5 points with paired 95% CI lower bound > 0; B precision >= A−2 points |
| Query latency | p50/p95 on same local machine, paired cold and warm runs reported separately | B p95 <= 0.80 × A p95 in each cache condition |
| Total cost | Ingest/rebuild/query CPU time, wall time, peak RSS, bytes on disk and query context tokens | At 20 queries/history, total CPU and context tokens <= A; sidecar disk <= 2× canonical patch bytes, peak RSS <= 128 MiB |
| Recovery | Corrupt/stale sidecar fails closed; authorized rebuild yields same exact event set as baseline | All frozen recovery cases pass; rebuild cost included |

Use the same bootstrap method, grouping all three queries by history. Always publish ingest/rebuild overhead and break-even query count; a query-only speedup cannot pass the total-cost gate. Zero canonical patch bytes makes the disk ratio undefined: report absolute bytes and UNKNOWN for that gate. Thresholds are predeclared for a later bounded local prototype and are not observations. Machine limits or changes to this protocol require a versioned amendment before a new run, retaining earlier failures. Passing does not approve installation, model use, or product integration.

## 4. Current deliverables and reproduction

Files live in [the synthetic fixture directory](../../experiments/redesign/hy-memory-experiment-fixtures/). `writer.json` has 20 named host-condition vectors plus a source-pinned candidate template. `diff-index.json` has 16 named outcome vectors, two distinct events sharing literal patch bytes, exact content/digest objects and paired baseline/sidecar reference manifests. Vectors are declarative scenarios: a future DUT harness must materialize each stated condition and test actual behavior; labels alone are not DUT execution evidence.

```sh
python3 experiments/redesign/hy-memory-experiment-fixtures/build_fixtures.py
python3 experiments/redesign/hy-memory-experiment-fixtures/validate_fixtures.py
```

Observed validator output:

```text
PASS fixture consistency: writer=20 diff=16; model_calls=0; DUT_runs=0; benefit=UNVERIFIED
```

Deterministic regeneration was checked. Four deliberate fixture mutations were rejected: missing-base UNKNOWN changed to EMPTY, source-content corruption, a sidecar target-revision mismatch, and duplicate delivery mislabeled as a new write. These checks exercise fixture validation only.

This is the full current evidence claim. Effectiveness experiments, blinded scoring, actual comparator/DUT behavior, latency, token savings, real Git-history retrieval, crash recovery and Rust-host integration are **not run / UNVERIFIED**. Future model or paid execution, private sources, weights/training, MemHub installation and production changes remain outside this authorization. Preserve REMORY's effectiveness-first gates and the closed RSI decision regardless of fixture validation outcome.
