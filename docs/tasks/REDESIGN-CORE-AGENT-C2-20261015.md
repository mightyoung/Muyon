# Core Agent C2 — independent process fixtures and dedicated CI

Current status: **25 final-contract process methods authored; actual corrected final run pending CI. Earlier compiled runs and their failures remain historical evidence, not final acceptance**. This author owns new `core-agent-lab/checks/`, `fixtures/`, `.github/workflows/core-agent-lab.yml`, and this task file only. Rust core belongs to another writer; no cross-write or author self-review.

Base `b53e63c195fc44380c4452fb5ddfedcd9c121d11`, unchanged product base `3b4a7b27afded3f2d3007028d793aa06bd564312`. Worktree `/tmp/Muyon-core-agent-checks-20261015`, branch `task/core-agent-checks-20261015`. P09 remains closed/parked at its preserved commit; P07/P08/old OC/CR work is not rerun.

## Fixed owned checkpoints

- `4f45b9c83997daf7f1c84ec3c586d1adcd33e836`: minimal dedicated workflow. Its title contains skip-ci; root combined it with a subsequent normal commit for actual CI, not a fabricated skipped result.
- `3a6accca578cbb6b24369bff7504f8444d1d7a9e`: removes manual workflow dispatch to retain only scoped push branches review/core-agent-* and develop.
- `e323d728d9c73a7222ca46b4bc0a4d79901a6d74`: independent 14 provider input scripts, 16 policy/loop expectation cases, and 21 process-test methods. Syntax check passed; this checkpoint does not claim runtime success.

The new workflow uses ubuntu-24.04's preinstalled rustc/cargo/Python, existing pinned checkout/upload actions and read-only repository permission. It records exact checkout SHA/tool versions; requires offline locked Rust tests, offline locked release build and then the Python process checker. There is no missing-checker or missing-tool success fallback. Initial Rust behavior RED stops before the absent compiled checker stage as intended. Tiny synthetic metadata/log/binary artifact retains one day; no private data/model/provider traffic or dependency installation.

Coordinator reports initial exact CI38665093404 on dfa3176e as compiled Rust RED: one passing and three semantic failing tests, preinstalled Rust/Cargo1.99.0. This is root-supplied checkpoint evidence, not this fixture author's local Rust execution or independent process acceptance.

## Independent inputs and checks

Input scripts and expected physical effects/state assertions were authored before reading DUT implementation; only public CONTRACT.md and writer's CLI.md were read. Initial/final pre-DUT SHA snapshots remain in `/tmp/core-agent-check-evidence-20261015/`. Provider events contain input-only tool/answer/fail tokens, no expected/golden/caseID or trusted policy flags. Expected assertion manifest is consumed only by the checker after actual execution.

Coverage planned in the committed executable checker:

- Input → real Rust fixture provider/tool request → trusted policy → physical effect/original receipt → subsequent answer, including actual trusted tool-result context substitution.
- Four modes; current confirmation; hard/scope/revocation/classification denial; FullAllow high/taint/new destination with zero extra risk confirmation. Model approval text/extra fields/aliases do not grant authority.
- Identical correlation/binding reuses original receipt; changed arguments cannot produce another effect. Provider/tool failure does not fabricate success.
- Cancellation before work or at dispatch; concurrent cancel after actual commit preserves original receipt and prevents another model call.
- Actual subprocess SIGKILL after flushed dispatch/effect/projection checkpoint notifications, using selectors and no sleeps. Effect and original receipt are one atomic physical snapshot, not invented separate receipt writes.
- Missing/not-found/corrupt effect evidence remains unknown; no reseeding or automatic dispatch. Physical receipt/count/value read independently from documented effects.db format.
- Persistent step/call/context/output/total-byte limits survive subsequent OS processes; invalid/zero/overflow limits and forbidden resume overrides reject. Synthetic bytes are not model token costs.
- Strict malformed hex/UTF8/events, completed-task replay and exclusive directory ownership.

Exact invocation from repository root:

```sh
python3 -B experiments/redesign/core-agent-lab/checks/process.py --binary experiments/redesign/core-agent-lab/core/target/release/muyon-core-agent-lab --evidence-dir /tmp/core-agent-process-evidence
```

Current verification: Python syntax valid, owned staged whitespace checks passed; actual process methods **NOT_RUN** until immutable compiled binary is available. Setup/import/missing-binary errors will be reported as errors, never behavior RED. Rust source is not modified or substituted by this author. Root assigns separate final spec/quality reviewers; this writer cannot non-author-review its own checker.

No installations, real models/endpoints/data/devices, credentials/licenses/payment, product/M03/schema/old-workflow changes, push/merge/deployment/deletion. M03 remains blocked_contract; real-model and native/platform acceptance are not part of this synthetic Agent loop. Remaining dependencies: immutable core implementation, compiled binary/CI execution, meaningful inverse mutation evidence and fresh non-author review.

## Provider correlation clarification and checker correction

Initial independent duplicate-provider-ref fixture expected a follow-up `once` answer. That was this checker's unsupported assumption: provider correlation does not grant host Binding replay authority. Coordinator ruled duplicate/conflicting provider refs must stop with `duplicate_or_unknown_call`, retain one physical original effect/receipt and no answer; typed host Binding replay remains separately required in Rust ToolPort tests. Only this author's fixture/assertion is corrected. Original fixture SHA snapshots remain external; source candidate `12bc52731ac06af729c110ab209ac629c0e9911c` already included the original expectation, so its actual first CI result must remain preserved rather than relabeled.

Public CLI now fixes context subrecords as ROLE<TAB>hexUTF8<NEWLINE>. Checks parse those distinct roles and require the actual physical receipt/value in a tool role before the final assistant answer, rather than accepting role-name substrings inside values. No implementation source was changed or used as an oracle.

## First actual implementation CI and second checker correction

Root supplied CI38665364085, exact source `12bc52731ac06af729c110ab209ac629c0e9911c`: Rust13 tests PASS, release compile PASS; independent21 methods had three assertion failures, preserved in `/workspace/reports/rd-core-agent-20261015/first-implementation-ci-full-decoded.log`. All three were checker assumptions: duplicate model ref expected an unauthorized replay answer; context subrecords were hex, not plaintext substring payloads; max_context1 was smaller than the initial input and correctly failed at start with input_context_limit. None is relabeled as a passing first run or a Rust implementation fix.

The context-budget checker now explicitly asserts that oversized initial input rejects with zero effects, then creates a valid empty initial context with cap16. Its actual subsequent tool-request response exceeds the cap before effect admission; the checker requires budget_exhausted, zero effects and unchanged persistent counters on reopen. This preserves both early admission and later growth checks rather than dropping context coverage. Actual corrected process results still await CI; local syntax and six harness self-tests pass only.

Workflow now requires checker harness self-tests and the author's core/mutations.py after baseline Rust/build/process success. Four compiling inverse behavior mutants must fail Rust behavior assertions; their command/logs and exact source/binary identity stay in the one-day synthetic artifact. No mutation source is accepted as implementation; no dependencies are installed.

## Current explicit contract, preserved ambiguity and exact source provenance

Current final checker source is `90575e8290c57fd2c67ffbca441b0d81baa81e8c`: 25 process methods plus six local harness self-checks. Actual final process and mutation outcomes remain NOT_RUN by this author pending root CI; no local binary was available and artifact download rejection was not bypassed. The preceding report's reject-both provider-ref ruling and blanket “all three checker assumptions” classification are historical, superseded by the distinctions below.

The public requirements before implementation are fixed independently of Rust DUT:

- `f68db20364caf38a48f09750d5137c88a70af552`, `experiments/redesign/core-agent-lab/CONTRACT.md:9,17–19`: input-only event grammar, empty final answer field permitted, stable host binding, duplicate/conflicting correlation checked, persistence and unknown lookup-only behavior.
- `b53e63c195fc44380c4452fb5ddfedcd9c121d11`, `docs/tasks/REDESIGN-CORE-AGENT-20261015.md:20–23,29,33`: provider call ID is correlation, exact host binding replay returns original receipt, altered binding conflicts, persisted cancellation/budget/context/provider position and counters; exhausted budgets survive reopen. These are the basis for terminal-preservation and physical no-second-effect assertions, not a presumed schema or implementation algorithm.
- `f68db20364caf38a48f09750d5137c88a70af552`, `core/CLI.md:15–22,28–36,56–64,68–75` under this lab: input bounds, task/start vs later execution, original-receipt tool context, before/after budget checks and physical journal/effect formats. Core CLI paths cited here are public interface documentation, not implementation inspection.

Three first implementation CI failures at immutable `12bc52731ac06af729c110ab209ac629c0e9911c` require distinct rationales:

1. **Repeated model reference — originally ambiguous, later explicitly clarified.** The preimplementation CONTRACT:17 said duplicate/conflicting calls are checked but did not choose identical-reference rejection vs lookup. Plan:20 required host-binding replay, not model-granted authority. The initial `once` expectation assumed the mapping behavior; the coordinator then prematurely ruled both kinds reject. That ruling produced checker `a438396a68d445dfc7f7ae8a8f9e86b0049d6445` and is preserved, not claimed to have been the only possible original interpretation. The new authoritative addendum `914ba02c0ab1a7c8b8c39ea26571de614342d216`, CONTRACT:19–25 explicitly fixes persistent ref→host-binding lookup: identical parameters plus verified original receipt reuse that fact with no second effect/confirmation; different parameters conflict; unresolved stays unknown. Final expected assertions are derived from this public follow-up requirement, not copied from the new implementation. The earlier `duplicate_or_unknown_call` fixture is retained in its immutable historical commit and the R1 RED reference only.
2. **Context role body — checker representation assumption corrected.** The initial checker searched plaintext receipt ID inside `context_hex`'s decoded subrecord text, though CLI:f68:68–69 only said those were UTF8 subrecords. Public clarification at immutable `6d25066f93bb982592e5f6754b19ac48a64a94f2`, `core/CLI.md:85–89` fixes ROLE<TAB>hexUTF8<NEWLINE>. The corrected checker decodes the body again, verifies distinct role tokens and actual physical receipt/value before the final assistant answer. This strengthens role evidence and does not weaken any expected effect, answer or permission assertion. It is not a Rust behavioral fix.
3. **Initial context1 — checker setup assumption corrected while preserving growth coverage.** Initial input has 20 bytes, so a context limit1 may fail closed at start; plan:b53:23 and CLI:f68:20,63 require limits before work and never promise admission of oversized initial context. Final checks explicitly require that early error and zero effect, then separately start with empty input/context16 so the later response causes persistent budget exhaustion. Follow-up CONTRACT:914:23 and root's explicit budget ruling also require admission accounting for the known bounded tool-result before the first effect: empty input/context40 + c1/hi must have zero effects. This is distinct from legitimate first-effect/next-call exhaustion, tested with max_calls1 and happy.tsv.

A separate nonimplementation reviewer must assess these rationales and the final fixture/source independence; this author does not self-certify them as final non-author review.

## R1 independent reproduction and final assertions

Reviewer-supplied discovery was attributed, not rediscovered by reading the DUT: terminal receipt-reconciliation cases and reference standalone probe `/tmp/core-agent-terminal-recovery-probe.py`. Two owned process probes were committed first in `17a4c8a96b93941a7b60a421869670b0c2c5603d` against frozen old review source `630d8b77f4e79a29481a6845d4099f553463c48d`; that commit preserves the old provider-reference fixture specifically to isolate R1 and is **not final clarified-contract acceptance**.

The terminal-tail probe runs c1/hi → done before an unreachable c2/later tail, withholds physical effects.db, observes unknown, restores byte-identical original receipt evidence, then captures lookup plus another real run. It requires the original single physical effect, receipt, done answer and two model calls to remain. The old bug reopens ready and executes c2, so the test observes the complete effect regression before asserting.

The frozen old budget probe used context40 and one already committed effect to expose lookup clearing budget_exhausted. Its exact empty `answer<TAB>` event has intentional trailing TAB required by preimplementation CONTRACT:f68:9; Git whitespace checking reports that fixture delimiter. No code whitespace issue is being hidden and the typed input must not be silently rewritten.

After the explicit before-first-effect ruling, final checker `90575e8` splits the responsibilities: the same context40 fixture must now have zero effects and a stable budget terminal; a separate valid max_calls1 task legitimately commits one effect and then exhausts at the next provider admission, and identical receipt restoration must not clear its terminal or any counters. The terminal-tail probe remains unchanged. Root will preserve the actual old-source R1 RED CI before testing implementation corrections; this report does not relabel a historical failure as passing.

Final additional same-reference tests use ask mode with exactly one trusted initial confirmation. After projection SIGKILL or actual response loss→unknown→lookup, an identical provider reference must return the original physical receipt and answer, preserve one effect and confirmation count1, and not create a second invocation. Different arguments require binding_conflict with zero extra effects. These directly implement addendum914, not model authorization.

No core source files, old labs, product entrypoints or dependencies were edited. Current work remains committed and preserved for root-only combination and fresh non-author review.

## Final whole-review R2 cross-path regression

Status: one new independent process regression authored; actual R2 execution NOT_RUN locally, awaiting intentional frozen-source RED CI. The preceding fixed CI's25 methods remain passing historical evidence; they did not cover this cross-path case. This is not a source fix or final acceptance.

New probe reuses existing two-effects.tsv with ask-every-time and one trusted first confirmation: physical effect1/original receiptR1, waiting second invocationI2, model_calls2, confirmations1. It withholds only effects.db by rename, records inspect/lookup/confirmed-run plus authoritative journal, restores byte-identical original receipt evidence, records lookup and a later fresh explicit confirmation, and only then asserts the complete trace.

Required behavior: missing prior original receipt evidence is lookup-only unknown even when current pending invocation differs; no added provider calls/effects, no consumed confirmation or rekey/new dispatch of I2. Restoration preserves waitingI2, exact prior receipt, original pending binding and counters. Only a later explicit confirmation may execute the legitimate second effect once and complete; physical receipt1 must remain byte-for-byte the original row. Confirmed-run while missing evidence may return exit2 error or structured outcome_unknown; the check does not invent a fixed failure-return convention. It never edits task.db or fabricates a receipt.

The requirement predates the fix: f68db20364caf38a48f09750d5137c88a70af552, experiments/redesign/core-agent-lab/CONTRACT.md:17–19 requires durable original binding/receipt and unknown lookup-only behavior; 914ba02c0ab1a7c8b8c39ea26571de614342d216, same CONTRACT:21,25,27 preserves original receipt verification, prior control barriers and unknown no-dispatch. b53e63c195fc44380c4452fb5ddfedcd9c121d11, docs/tasks/REDESIGN-CORE-AGENT-20261015.md:20–23 requires original receipt identity, uncertainty hold, confirmation/hard-prerequisite separation and persisted counters. A new confirmation cannot replace missing hard evidence. These public requirements—not the eventual source fix—define assertions.

Attribution: final non-author reviewer supplied the discovery and external reference `/workspace/reports/rd-core-agent-20261015/final-waiting-receipt-probe.py`; this check adapts that exact physical/command scenario into the owned process suite. No duplicated independent discovery or final self-review is claimed. Full external trace r2-trace.json preserves both command conventions and journal observations before any behavior assertion, including an old-source failure that might otherwise stop too early.

Local six harness self-checks PASS, Python syntax valid. Actual Rust/kernel regression remains NOT_RUN locally; no compiler/binary installation or artifact403 bypass. Root will preserve frozen old source and first actual R2 failure before testing a separate writer correction. No DUT files, fixtures, dependencies or workflow are changed by this checkpoint; owned changes only checks/process.py and C2 taskdoc. No push/merge/install/real model/device/credentials/license/deletion.
