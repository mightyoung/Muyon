# SDD ledger — plan: docs/superpowers/plans/2026-10-23-connectors.md

X2 consumes exact C1/C2 release composed at 4d49a580cb518d9b0b80c9df3df1ff564194a639; no shared types copied. Contracts alone registers modules.

RED source 2f8842c08ae0d774fc54a1a198b6ac5c3a0eb09a: 0 passed/6 failed after successful compilation. GREEN 6 passed/0 failed. Strict core/all-target Clippy -D warnings exit0. Whole-workspace offline/locked regression in progress; not yet a completion claim.

Ruling: recovery_for Unknown delegates existing C2 unphased_host_error and preserves original IntentId; NotDispatched/Confirmed return only that original lookup identity — no branch grants replay or returns a Receipt — future host integration must not mistake Ok(identity) for authorization or business success.

Ruling: host supplies current binding/scope/per-plugin allowed set within a trusted pre-dispatch critical section and revalidates original C2 scope/authority — the pure validator cannot attest provenance of arguments — production dispatch remains unavailable until concrete Operation, trusted host identity, consent/disclosure/budget and lifecycle mapping are separately reviewed.

Tests use in-memory timeout/lookup fixture, C2's actual decode_original, and production validate_call/recovery_for. Fake assertions do not establish live protocol/lifecycle support. No credential/OAuth/revoke/network/SDK installation or second execution ledger.

Final review: independent reviewer /root/review_connectors_x12, fixed source86534f4126835b46af3c7ec818de184491128be9; no P0-P2 findings, separate-target focused13/13. Final minor (deferred): actual disconnect/remote failed-revoke transition coverage is absent; fake flag/counter do not establish live lifecycle behavior, which remains gated/NOT_RUN. Whole workspace632/632, strict core Clippy and changed-file format pass. This completes the local source slice only; Contracts registration and production host gates remain pending.

## Lifecycle follow-up

Latest develop e943856e4b6e2de26a9c2c8e2fa0912713b590e5 contains reviewed C1-C3/root toolchain. Ordinary merge refreshes this candidate; no shared registration edits. Read the new plan-review addendum; suggested architecture/dependency changes remain suggestions.

Ruling: add a borrowed host admission view plus pure candidate-transition validation, not configure/connect/revoke command APIs or a state store — approved X2 calls for pure lifecycle checks while concrete Operation/host identity/SDK gates remain open — future live integration must still supply trusted provenance and original C2 checks.

Ruling: local disconnect and disable preserve auth/token knowledge but increment the existing authorization_generation exactly once to invalidate old prepared bindings; overflow rejects without applying state — no second session epoch introduced — a later host integration must adopt or explicitly adapt this generation policy.

Ruling: unsuccessful remote revocation is represented as auth Unknown, never Revoked; lifecycle validation errors carry unknown/after_lookup and optional original IntentId, rather than proving a remote action was not dispatched — actual server revoke stays NOT_RUN.

Lifecycle complete at local pure/fake scope: RED e1bbeadfa2800bd64bf58aad199279c8e110c8f4 (6new failures), GREEN1afb93e47114b052411b7ccac1fbf175380cdedb (19/19 focused); clean-source workspace638/638, strict Clippy/fmt exit0. Independent review /root/review_connector_lifecycle: noP0-P2, separate-target19/19. No new deferred code finding. Real lifecycle/host/Operation remains gated.
