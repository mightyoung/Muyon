# Android development draft integration report

Date: 2026-10-23. Status: local implementation and targeted verification in progress; final combined verification pending. This report separates the successful PR119 baseline from the subsequent local candidate and from external acceptance that has not occurred.

## Source and hosted CI baseline

PR119 source b899a326 has successful hosted product run 39954301010 and generic CI run 39954301004. Neither run failed or required a rerun. These results apply to that source; the later local native/Service/UI changes are not covered by those hosted results. No PR108 change or merge is included in this work.

## Local implementation

- Added `DevelopmentDraftHost` and generated UniFFI wiring for the persistent local development-draft route.
- Connected the Service-owned controller and development UI to the native host, retaining scope/session authority in the host and Service boundary.
- Added development_draft_propose only to an explicitly selected, restricted development chat catalog. Proposal acceptance is source-bound and consumed locally; scripted responses do not count as a live model-chat acceptance.
- Added cross-database freeze/acknowledgement and recovery handling so acceptance and durable save retain the original request and save intent across failure/recovery.
- Addressed stale `scope_generation` reuse after A→B→A, exact displayed plan ID and binding digest, and JSON number-type preservation. Restoring the same complete command retains its owner plan. An interrupted proposal with no save acknowledgement remains pending until an explicit cancellation of its original request; recovery never applies it automatically.

These changes implement the local development-draft path. They do not establish a production-authorized executor, live provider chat, or external connector synchronization.

## Verification ledger

The following targeted results were supplied by the implementing/root agents. Final command outputs and final-candidate coverage remain the root agent's verification responsibility.

| Gate | Current evidence | Acceptance limit |
| --- | --- | --- |
| PR119 hosted product CI | Run 39954301010: success at b899a326 | Baseline source only |
| PR119 hosted generic CI | Run 39954301004: success at b899a326 | Baseline source only; no failure/rerun |
| FFI targeted tests | 8 passing | Targeted bridge behavior; not a full workspace result |
| Core-agent development tests | 7 passing | Scripted/local development behavior; no real provider request |
| Controller/UI targeted checks | Controller/runtime checks and 6 UI-state checks pass with `-Werror`; four Compose test sources added | Compose compilation and execution listed separately below |
| Final workspace tests | `--workspace --all-targets --offline --locked -- --test-threads=1`: **771 passed / 0 failed / 0 ignored**, 49 summaries, exit 0 | Execution counts include repeated source-harness coverage; not 771 distinct product scenarios |
| Final Android Gradle compilation and tests | Pending | Root to add final command/result/source evidence |
| Strict Rust Clippy | `--workspace --all-targets --offline --locked -- -D warnings`: exit 0 | Local candidate, no runtime/provider claim |
| Android Rust targets | aarch64-linux-android and x86_64-linux-android checks: exit 0 | Rust compilation only |
| Final Android lint | Pending | Root to add final command/result/source evidence |
| Hosted CI on final candidate | Pending | Earlier b899a326 runs cannot close this gate |

## Remaining external and product acceptance

- Production budget proof remains unavailable and the existing `send_allowed` gate blocks sending. No real model request was performed. Live provider chat and production authorization execution remain unaccepted.
- Real OAuth/WebHook synchronization has not been accepted; this local work does not close repository-connector integration.
- Skill/Connector execution and Reader/FD integration remain outside the completed local path and unaccepted.
- Android physical-device acceptance has not been performed. JVM/FFI/compiler/lint evidence does not substitute for device behavior.
- PR108 remains visually unaccepted and untouched. The complete production page set and the new development UI still require the applicable visual acceptance.

## Completion conditions

One initial full run exposed a pre-existing quota fixture timing dependency: preparing roughly 150 MiB of synthetic journal data could outlive a 20-second document grant. Its isolated rerun passed in 16.82 seconds. The fixture now grants the exercised copy operation after bulk setup, using the same unchanged production expiry. The subsequent complete workspace run passed; no production timeout, admission rule or assertion was relaxed.

Local raw outputs: `/private/tmp/muyon-development-tests-final.log`, `/private/tmp/muyon-development-clippy.log`, `/private/tmp/muyon-development-android-rust.log`, and `/private/tmp/muyon-development-gradle-compile.log`. These temporary files are local evidence, not durable hosted artifacts.

Record final workspace, Gradle and lint results and hosted CI for the final candidate. Independent production-boundary and UI callback reviews found no remaining blocker after the four repairs above; this is a source-review result, not visual or device approval. Preserve every external/visual/device gate above until its own evidence exists. Overall production delivery remains incomplete.
