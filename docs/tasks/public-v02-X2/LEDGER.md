# SDD ledger — plan: docs/superpowers/plans/2026-10-23-connectors.md

X2 consumes exact C1/C2 release composed at 4d49a580cb518d9b0b80c9df3df1ff564194a639; no shared types copied. Contracts alone registers modules.

RED source 2f8842c08ae0d774fc54a1a198b6ac5c3a0eb09a: 0 passed/6 failed after successful compilation. GREEN 6 passed/0 failed. Strict core/all-target Clippy -D warnings exit0. Whole-workspace offline/locked regression in progress; not yet a completion claim.

Ruling: recovery_for Unknown delegates existing C2 unphased_host_error and preserves original IntentId; NotDispatched/Confirmed return only that original lookup identity — no branch grants replay or returns a Receipt — future host integration must not mistake Ok(identity) for authorization or business success.

Ruling: host supplies current binding/scope/per-plugin allowed set within a trusted pre-dispatch critical section and revalidates original C2 scope/authority — the pure validator cannot attest provenance of arguments — production dispatch remains unavailable until concrete Operation, trusted host identity, consent/disclosure/budget and lifecycle mapping are separately reviewed.

Tests use in-memory timeout/lookup fixture, C2's actual decode_original, and production validate_call/recovery_for. Fake assertions do not establish live protocol/lifecycle support. No credential/OAuth/revoke/network/SDK installation or second execution ledger.

Final review: independent reviewer /root/review_connectors_x12, fixed source86534f4126835b46af3c7ec818de184491128be9; no P0-P2 findings, separate-target focused13/13. Final minor (deferred): actual disconnect/remote failed-revoke transition coverage is absent; fake flag/counter do not establish live lifecycle behavior, which remains gated/NOT_RUN. Whole workspace632/632, strict core Clippy and changed-file format pass. This completes the local source slice only; Contracts registration and production host gates remain pending.
