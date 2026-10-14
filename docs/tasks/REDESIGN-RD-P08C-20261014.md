# RD-P08C Android source and pure-JVM presentation slice

Writer branch `task/rd-p08-android-20261014`, base `25bfb3180111b156b8ba567fd14c7cca101d3e13`; worktree `/tmp/Muyon-rd-p08-android-20261014`. Scope is new `experiments/redesign/device-deferred/operable-supplier-flow/android/**` plus this task report. P07/product/schema/build/CI and other writers' files remain unchanged. No push or merge by this writer.

Delivered typed host projection/action port and a source-only Compose phone list → detail → full editor. The model receives host status/preview/current row/original receipt, holds local navigation/raw buffer and forwards narrow actions. No JSON codec, transport, JNI, name validation/normalization, CAS, intent allocation, receipt synthesis/digest verification or business persistence is added. The experimental DTOs correspond to the shared P08 host boundary, **not a frozen M03/production schema**.

| Task criterion | Result / evidence |
| --- | --- |
| Read shared boundary, D01.1 and Android addendum, preflight, repository REVIEW | Done; shared host writer confirmed session/recovery and original receipt fields; no AGENTS in source hierarchy, workspace `.agents`/`.codex` empty |
| Stable ID, exact decimal revision, exact raw UTF16 callbacks | JVM covered; `SupplierScreenModel.kt:5`, `:82`, `:98`; large u64 decimal text and raw whitespace/combining/control/lone-surrogate samples remain unchanged |
| Conflict draft/current row/original expected revision | JVM covered; `SupplierScreenModel.kt:55`, `:63`, `:79`; no silent rebase; only host Revision conflict permits explicit discard then fresh edit |
| Original receipt versus current row | JVM covered; `SupplierScreenModel.kt:9`, `:64`, `:79`; original receipt retained as supplied, historical revision 2 versus current revision 3, missing current read not filled from receipt |
| Unknown/restart projection and action routing | JVM covered only; original advertised session restore port is GET, no implicit rekey; saving/unknown or uncertain save cannot cancel, change raw or save again; original lookup remains available |
| Draft/preview/save callbacks and navigation | JVM covered; in-flight double clicks suppressed, rapid raw synchronized serially, unsynchronized draft preserved across selection/failure; session switch blocked while local raw unsynchronized; explicit discard/keep confirmation |
| Compose source page and accessibility provisions | Source present: `SupplierPage.kt:43`; same-ID navigation, full-screen editor, labeled actions/status/heading semantics, system back, 48dp actions, in-flow scrolling with IME/system padding; all runtime properties NOT_RUN |
| Actual pure-JVM RED → GREEN | Done, complete new suite 24/24 passes; logs outside Git below |
| Native Compose compile/launch/transport/device/accessibility | **NOT_RUN**; platform dependencies/native composition unavailable, no install attempted |
| Browser mobile evidence | Separate host/desktop/integration task; no browser evidence relabeled Android |

Validation with preinstalled Kotlin 2.2.20 and JDK 17, no dependencies/downloads:

```bash
./experiments/redesign/device-deferred/operable-supplier-flow/android/run-jvm-tests.sh
bash -n experiments/redesign/device-deferred/operable-supplier-flow/android/run-jvm-tests.sh
git diff --check
```

Initial writer suite: **24/24 JVM projection/action checks passed; native Compose NOT_RUN**. Round-one evidence below supersedes that original completion status after two independent review findings. These tests inject synthetic typed projections into the real presentation model and record callbacks. They do not execute actual Node host, Rust, SQLite, HTTP, Android/Compose or a device. The complete new JVM subset is run; closed P05/P06/P07 suites and unrelated product suites were not rerun under the delegated task boundary. Test runner writes only new `/tmp` jars and preserves them for review.

RED evidence is retained under `/workspace/reports/rd-p08-flow-20261014/android/` outside Git. First compiled RED: `jvm-red.log`, 15 failures / 16 checks, first `FAIL stable supplier ID and decimal revision stay exact: presentation action not implemented`. Guard RED `jvm-red-guards.log`: 3 failures / 21 checks (save/preview raw lock, unverified-saved cancellation, retained draft refresh). Navigation RED `jvm-red-navigation.log`: 2 failures / 24 checks (unsynchronized local raw on selection/session change). Fresh final GREEN: `jvm-green-final.log`, 24/24, exit 0. No original failures were erased. No raw log is committed.

Outstanding dependent acceptance: non-author review/integration by Leader B; actual Android host adapter and Android/Compose dependencies, native compile/render/load, TalkBack, IME, rotation, 200% fonts and device execution remain NOT_RUN. M03, real authority/grants, production retention/migration and full D01.1 are **blocked_contract/out of this experiment**. Host-acknowledged raw may be durable under host rules; unsynchronized local raw has no Android process-recreation guarantee. This source/JVM slice alone is not cross-platform/native acceptance.

## Round one: independent recovery review fixes

Non-author review of immutable `ef056ea80495b47f651ed2461bb64b96bfc69901` required changes for two P2s: preview-unavailable recovery affordances (`SupplierScreenModel.kt` original lines 56–63 / `SupplierPage.kt` 159–164) and uncertainty leaking/clearing across restored sessions (original model lines 53, 143–146, 175). The full review is outside Git at `/workspace/reports/rd-p08-flow-20261014/android-review-ef056ea.md`. Those original 24 passing checks did not cover either failure; the independent three-probe repro failed 0/3 against the immutable original.

Fixed only the owned presentation slice. The host's exact `unavailable` plus `preview_unavailable` reason proves its preview failed before dispatch, so this editor can change raw, retry preview or explicitly discard without invoking a rejected lookup. Save still requires a new successful host preparation. Other unavailable reasons stay locked, and a prior uncertain save cannot be cleared by a stale preview-outage projection. The source page displays preview retry guidance through the model's guarded affordances.

Local uncertain outcomes are now correlated by exact original `(session, intent)`, with no new wire fields or business authority. Switching to editing/rejected session B neither locks B with A's result nor clears A. Returning stale prepared A still exposes lookup and blocks save. Unknown/saving projections retain their own guard; only a host-supplied saved receipt, rejection, or confirmed Revision conflict for that exact original key clears it. A different intent cannot clear the original guard, and the host saving label remains distinct from unknown transport outcome. No draft/binding rekey, business reducer, schema or transport change was made.

`RecoveryProbe.kt` is a byte-identical copy of the reviewer's unchanged three repros (SHA256 `8fecfe602c179a1879db2072ff54ff004fc1d068d516b011621b8f324726e216`) and the runner executes it in a separate JVM jar. Nine additional main-suite checks cover precise outage affordances/raw/retry/discard, arbitrary unavailable rejection, session/intent-scoped uncertainty and resolution, stale outage guards, and preserving host saving display. Original tests remain intact.

Preserved fresh RED/GREEN outside Git under the same Android evidence directory:

- `jvm-round1-red.log`: original suite 24/24; unchanged independent repro **0/3**, exit 1, reproducing all supplied failures before implementation.
- `jvm-round1-expanded-red.log` / `jvm-round1-expanded-red-assertions.log`: expanded suite 25/30, five failures before correction. The first run reported an empty-action-list exception for missing preview dispatch; the second uses an explicit action-count assertion and preserves the original first output.
- `jvm-round1-green.log`: main suite 30/30 and unchanged probes 3/3 after the two P2 corrections.
- `jvm-round1-saving-label-red.log`: main suite 32/33, one failing saving-label guard uncovered while ensuring the original host phase remained distinct; no earlier evidence removed.
- `jvm-round1-final-green.log`: fresh final **33/33 main JVM projection/action checks**, separately **3/3 unchanged independent recovery probes**, exit 0. These counts are reported separately because some cases prove overlapping behavior. Two jars retained under `/tmp/rd-p08-android-jvm.RDWqC6/`.

Shell syntax and `git diff --check` pass. Native Android/Compose/transport/accessibility remain **NOT_RUN**, M03 **blocked_contract**. The correction still needs scoped non-author rereview before integration; passing writer checks do not self-approve the prior P2 findings.
