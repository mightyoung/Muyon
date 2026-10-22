# RD-P06 — isolated synthetic durability and restart

Status: implementation fixed; author RED/GREEN complete, non-author verification and candidate CI pending. No intake decision.

Authorized following closed RD-P05. Baseline `676331048611aa1fb0f226ec300f6bac633e98a0`; isolated worktree `/tmp/Muyon-rd-p06-durable-20261014`, branch `task/device-deferred-durable-recovery-20261014`. Directory `experiments/redesign/device-deferred/durable-recovery-lab/` and new task documents are the entire scope.

Leader B owns `CONTRACT.md`, this task, evidence coordination and any later intake. Original Rust domain writer owns `core/` and `REDESIGN-RD-P06A-20261014.md`. Original Rust recovery reviewer owns external independent evidence only; fixed-SHA review follows implementation. Existing writers, worktrees and raw evidence remain preserved. No duplicate writer was created after the connection interruption; actual exec and remote Git queries confirmed restoration.

Read D03a original contract/experiment and design memory/ledger constraints first. See [bounded lab contract](../../experiments/redesign/device-deferred/durable-recovery-lab/CONTRACT.md). Pending identity is not zero-dispatch proof, projection is not receipt authority, and an in-memory reducer is not durable evidence. Synthetic persistence cannot authorize real chat retention, memory extraction, backup/tombstone restore, or product schema freeze.

Only existing offline dependencies and synthetic Linux temporary directories. No product/schema/CI configuration edits, production databases, real models/devices, new installation/licences or MUYON_EVAL_REAL. Android/Compose/Electron runtime remain NOT_RUN; M03 remains blocked_contract. No main change, force push, delete or deploy.

Delivery requires subprocess/fault RED before GREEN, necessary behavior mutations with byte restoration, immutable non-author review, full source SHAs and fresh candidate CI terminal status. Raw logs stay outside Git. RD-P05 first SQLite RED remains unexplained; completed historical CI is not rerun.

## Fixed delivery and candidate

Author source `c925d4274b2bccf95ac48b4040e4d0db2548f5ca` is clean and unmodified in the candidate. Author reports 26 subprocess tests passing, 8 exit fault boundaries, 2 SIGKILL barriers, and four behavior mutants compiled successfully then failed assertions; byte restoration followed by GREEN. These are author results until independently rerun. Raw logs and 42 physical effect-file observations remain outside Git at `/tmp/rd-p06a-evidence-20261014/`.

Non-author clean checkout `/tmp/Muyon-rd-p06-independent-20261014` fixes the author SHA. Review must include complete suite, source/physical effect binding, single-state rollback, strict read-only unknown recovery, projection/receipt isolation and necessary mutations. Report outside Git: `/tmp/rd-p06-independent-20261014/REVIEW.md`.

Candidate branch `review/rd-p06-combination-20261014` starts from the author SHA and changes this coordination document only. Latest develop is still the baseline. Candidate CI checks existing Flutter regressions; it does not execute the Rust lab and cannot replace exact-source subprocess/fault/mutation verification. CI may run concurrently with independent review; any review blocker prevents intake regardless of CI success. No merge into develop/main is performed by this review step.
