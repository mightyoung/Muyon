# Core Agent C2 — independent process fixtures and dedicated CI

Status: **workflow and independent-check checkpoint committed; actual independent Rust process run pending compiled implementation**. This author owns new `core-agent-lab/checks/`, `fixtures/`, `.github/workflows/core-agent-lab.yml`, and this task file only. Rust core belongs to another writer; no cross-write or author self-review.

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
