# Reader FFI recovery — fixed-develop scope before changes

Base c130008bbc40d78e85d10058030da9da4aca38f0 (PR101 already merged).
Independent worktree/branch task/reader-ffi-recovery-20261022. Original worktree
remains1c64ab50021c6183f281ee32f751f2a2876a4e45, clean; no pending Group gate edits
or commits after that source. Early failed Git fetch did not imply rollback: we
checked status/log/reflog and the original branch before new work. Both fixed
sources now fetch successfully; no credentials/security/cost configuration changed.

## Minimal deliverable now

Only this task directory: real dependency-free Rust correlation types/validation,
negative tests, exact source comparison and adaptation checklist. Source artifact
adapter/reader_policy_bindings.rs is NOT registered in lib.rs, NOT generated UniFFI,
NOT a new policy endpoint and NOT authority. It is tested Rust input/callback
validation ready to reuse after the concrete Core API is verified. No successful
stub, mock policy port or copied authorization table. Original requests and receipts
remain core-owned; syntactic correlation equality never authorizes a display/grant.

No edits to production FFI/lib, Core/lib/documents, Office/Bot, generated bindings,
Android Service/Runtime/UI. No old branch merge. B retains sole integration and
binding generation. Prepare tests first, retain actual RED and final outcomes,
independent read-only review and immutable source SHA normal push.

## Actual source differences/dependencies

Develop has no document_bridge.rs/tests and no old presentation policy wrappers.
5488ec69d59ae2ed368ca2fd53d5989c51cf2719 contains those3FFI files, but depends on
older Bot/Core composition. 1c64 contains doc approval, not admission implementation.
Do NOT cherry-pick the whole branch or overwrite current Office/Bot work.
Host660f03da29d26d6cdcf28c594c959cc6c43098e4 is the seven-endpoint contract, supplemented
by actual initial-read approval at2026-10-22T09:23:33Z. Core be902 A–D are partial
per parent; no verified fixed E/F/G/admission source has been delivered here.

Group5f2644cfbcc580a0cc9a567c5272d58c35b47ac3 has actual provenance/gate/tool history;
current develop lacks request_origin/group_request_gate/group_prepare_chat and
canonical binding namespace. Old Group work never reached source changes locally.
Separate Group gate remains HOLD until fixed dependencies are composed and missing
namespace behavior is made conservatively observable without creating it. Detailed
request-only insertion points and namespace issue are in ADAPTATION.md.

## Tooling and verification boundaries

Use product CI's fixed Rust1.93.1 (.github/workflows/muyon-product.yml:43), downloaded
from official static.rust-lang.org into workspace/task-tools/reader-ffi-recovery,
verify official SHA256 before extraction. No system install, elevation, credential
configuration, purchase, SDK/Flutter or real model/search/engine request. Dependency-
free rustc tests are actual execution; distinguish them from cargo workspace/FFI,
which still needs locked dependencies and verified Core integration. No device,
physical visibility, PFD disposal, >30s reading or verified gate acceptance claim.
