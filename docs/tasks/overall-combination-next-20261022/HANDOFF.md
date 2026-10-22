# Next combination handoff — Rust/FFI tested, product gates pending

Old batch frozen remote lab/overall-combination-20261022 atd5a2ff0f, tested code
7b7d8062: strictClippy0 (authorizedsave-onlyABIallowance), workspace435PASS,
independent final source review. New counts below never retag old results.

New branchlab/overall-combination-next-20261022; fixed sourcef604f0a56dc5e69874570ba3c4dd2f54ef427594.
Pins: corefaeef3ae+transaction721077; provider7bb89a71; Hostf7072ca2;
Botdefinitions4d81ae67 (only ownmodule, no098d overwrite); Shellf04f4ef2
(ownUIonly, retain Hostf707). Other old reviewed modules retained. Matrix/ledger
and sourcehashmanifest record full immutable values and exact composition fixes.

Actual productRustworkspace576executionsPASS/0FAIL/0ignored,30groups,FFI15/core561.
Includes provider26/Botdefinitions33/bridge8; worker48/group95 contain repeated
modules, group95=47group+48repeated. Not576 independent cases. Compilation initially
failed group harness missingdocuments; realmodule added, actualalltargetcompilePASS.
Host nativecodec/save-state/session/projection JVM runnersPASS; Shell oldfakeprepare
signature failed then minimalrecord signature fix retained forbiddenbody; all3Shell
checksPASS. StaticPythoncheckers17PASS; actual5-bindgen repeated/cmpPASS.

Host deliverable: single generated commitf604f0a56dc5e69874570ba3c4dd2f54ef427594,
file apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/productbridge/muyon_android_product.kt.
Actual LocalDraftPrepareRequest namedfields and methodline in FIVE-METHOD-HOST-HANDOFF.md.
Parent should hand this to originalHostowner. Existing Service patch mapping
applychecks successfully but remainsUNAPPLIED; verified=false/prepareunavailable.
Only originalHostowner releases real Service source/accepted gate. Lookup now
fences a preparation and is NOT a pure read. No ordinaryUIread auto-lookup.

Remaining newbatch quality fixes, pending original authors, not denied operations:
- core candidate.rs:297:19 unused publication hook (must not remove/enable hard
  publication gate just to silence lint); documents/mod.rs:19:21/37 unusedreexports
  in worker and group-harness contexts also emit realwarnings.
- bot_definitions.rs:207:12 nonminimal_bool, source owner equivalent simplification.
Strict workspaceClippyFAIL101, downstream lint targets not yet proven. Preserve
save-only explicitly authorized ABIargumentcount allowance, no global exceptions.

Android compile/lint/deviceNOTRUN(existingSDK/Gradle absent,no SDK-denial bypass).
Actual Service save/restore/query UI dispatch remainsclosed. Candidate objects/pins
are real unvalidated preparations, both publish routesharddeny; no real validator,
Office/model/search execution/credentials/fees or full-product acceptance. Bot
creation module runnable=false, no actualUIcreate. Forms65fb deferred; newReaderff3cc,
Group96d90,Office7fb2 Important inputs excluded. Source resolver/reader/canonical
RunLedger/gateway/evidence caller integration remains their originalowners.

No PR/main/develop merge/deploy/forcepush/branchdelete, no old403/I04 rerun or old
Unknown/¥0.002620 change. No CI dispatched or CIpass claimed. Finish by preserving
all raw failures/NOTRUN and sourcehashes. Current integrator changes limited to
module composition, genuine harness dependency, forbiddentest port ABI adaptation,
runner conflict resolution and actual generatedbinding. Fixedsource independent
review complete; sourcequality/Host/device gates still pending via parent.

## Bot archive flag lint closure — independent minimal patch

2026-10-22 UTC. Independent fix branch: `task/bot-definition-clippy-20261022`,
based exactly on this handoff's `b13af1124ed1b078609a3b36fcf4f56e5ec27567`.
Code-only commit: `3066475d6a8dd19e25e8608de81eaf2cab881727`.
Only one line in bot_definitions.rs changes: `!A && !(i == 2 && B)` becomes
`!(A || i == 2 && B)`. No lint allow, removed check, publication change or
provider/binding import. Tests and all scope/schema/type/draftCAS/entry/tail
checks remain byte-identical. This source is byte-identical to independently
reviewed equivalent owner commit `c65d6e3ec1ed1f50566bde705729c221f4c9f90a`.

Actual new verification uses Rust/Clippy1.93 and the real b13 combination plus
that single-line patch, not the historical098d combination runner. Provider7bb,
FFI lib.rs and actual generated productbinding before/after SHA256 match the
b13 originals. Production source/actual binding files were never overwritten.

- `cargo test --manifest-path crates/Cargo.toml -p muyon-core --lib bot_definitions -- --test-threads=1 --nocapture`: **33passed/0failed/0ignored**.
- Original five independent probes, temporarily appended only in this isolated
  combination worktree and run with qualified `bot_definitions::tests::independent_`:
  **5passed/0failed/0ignored**. Initial broad filter also ran two unrelated
  tests (7allPASS), but the capture harness expected5 and exited; those original
  logs are retained under `initial-broad-filter`, not relabeled as productFAIL.
- All8 prior author behavior mutations and both independent delete-entry/
  delete-tail mutations recompiled and failed behavioral tests as expected;
  no compile failure counted as a kill. All temporary mutations/probes restored.
- Independent reviewer compiled the actual old/new Rust expressions and
  exhaustively compared **196608** index/byte-pair inputs: all equivalent.
  Review confirms only that syntax line differs; independent does not claim
  a second current-combination33/5 execution.
- Scoped rustfmt PASS. Scoped `cargo clippy ... -p muyon-core --lib -- -D clippy::nonminimal_bool` PASS.
- Full `cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets -- -D warnings`
  remains **FAIL101**: `documents/candidate.rs:297` unused
  `document_publish_candidate_in_transaction`. Bot nonminimal_bool diagnostic
  is gone. This patch adds no allowance or changes another owner's hard gate.
  Later blocked lint targets remain unproven; no new576/workspacePASS is claimed.

Raw commands, UTC, exits, protected hashes, actual failures and independent
review are under `evidence/bot-clippy/`. Independent metadata SHA256:
`caf586ff0c90c74d92eae3ffc3c0bcd2e5b104a55a4fbd14dca06e14810724b7`.
Run `sha256sum -c SHA256SUMS` from that evidence directory. Raw Cargo logs retain
original whitespace. ParentB still owns composition/integration; main/develop,
Service/Android/device gates, real providers and old unknown/reservations unchanged.
