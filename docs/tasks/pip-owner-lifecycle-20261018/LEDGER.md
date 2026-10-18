# PIP-05/06 execution ledger

Base: `05d224f4b4fb31b3e015ea88cdaa7a14b03978b8`.
Ownership source: `52906b50db1825c165ac237a7f7a21efdc5a0bbf`.
Approved design: original audit README short design plus parent's explicit
continuation for owner/generation/lease/disposer and admission/drain/release.

Ruling: optional trusted Rust managed enrollment; no new wire lifecycle command
and no implicit migration of existing host enrollment — keeps current backend
integration compatible; host must explicitly adopt the new seam before claiming
end-to-end per-bundle drain.

Ruling: host callbacks acknowledge actual quiescence/persistence/close; Catalog
only fences and tracks them — host paths are excluded and Catalog cannot observe
their resources. Cost if a trusted host misuses this contract: premature release;
documented adapter preconditions and integration review remain mandatory.

Commands run from repository root with CARGO_HOME=/workspace/pip-toolchain/cargo,
RUSTUP_HOME=/workspace/pip-toolchain/rustup and
CARGO_TARGET_DIR=/workspace/pip-lifecycle-target. Toolchain Rust/cargo1.90.0;
locked/offline; no manifest/dependency additions.

1. Wrote owner_lifecycle integration tests, then supplied a compilable refusing
   API around the old Catalog; no compile failure counted as RED. Command:
   `cargo test --locked --offline --manifest-path experiments/redesign/plugin-contract-lab/core/Cargo.toml --test owner_lifecycle`.
   Actual RED exit101:0 passed/9 failed, missing owner lifecycle semantics and
   untracked wire bypass. `evidence/owner-red.log` and `refusing-api.rs.txt`.
2. Implemented owner identity/exact disposal/dependency fencing/retained work and
   host settlement/release callbacks. Same test command exit0:9/9;
   `owner-green-initial.log`. Full original crate exit0:31 passed (22 original+9),
   `suite-green-initial.log`.
3. Added five supplementary quota/result/exact-removal/JSON-injection/host-marker
   cases, not claimed as new feature RED. Full crate exit0:36 passed;
   `suite-green-expanded.log`.
4. Added cancellation observation test and temporarily false accessor. Exact
   test `stop_wire_cancel_and_close_request_cooperative_cancel_without_settling_work`
   failed with "missing cooperative cancellation on stop", exit101:1 failed,
   14 filtered; `cancel-red.log`. Implemented atomic cooperative flag shared by
   WorkLease and retained work; stop/cancel/close request it without settlement.
   Full suite exit0:37 passed (22 original+15 lifecycle), `suite-green-cancel.log`.
5. Formatted new module/test only with rustfmt --edition2021
   --config skip_children=true; preserve existing compact shared lib.rs style.
6. Fixed implementation source `853687cb0ce7d7e0133808f05a07258175c6b486`,
   tree `133e03b30b57f8ead0aa687537d149173b105bb6`. Author's fresh locked/offline
   full crate37, unchanged audit supplement4 and scoped rustfmt all exit0.
   Command arrays/time/exit/log hashes in `evidence/fixed/MANIFEST.json`.
7. Fresh independent review at the same fixed source: full crate37, audit4,
   rustfmt all exit0; three separate external probes pass. No blocking finding
   or required source fix. See REVIEW.md and `evidence/independent/`; caught
   panic output is intentionally preserved. External probes do not inflate the
   committed37 count. Review record/doc clarifications do not change code/tests.

Integration rulings accepted: trust preconditions for actual host quiescence and
receipt persistence stand because those resources/paths are excluded; legacy
consumer dependencies conservatively block selective provider unload; callback
panic state retention does not certify host lock/external-effect recovery.
These are documented limits, not waived test failures or production acceptance.

Only this task's docs and plugin-contract-lab source/test files are changed.
No host source/test suite, store migration, Android/UI/OCR, I04 flow/HTTP/reopen,
real data, model, permission/credential, main/develop merge or deployment ran.
Earlier audit supplement remains available; already completed PIP-00/04/07 work
is not reimplemented. No test or check was weakened to obtain success.
