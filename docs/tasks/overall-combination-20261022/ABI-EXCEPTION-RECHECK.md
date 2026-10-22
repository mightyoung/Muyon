# Explicit fixed-ABI exception — actual current-source checks

Codec628e23e4040a272156025098b3e5b6ea9bd9ead imports provider-owner patch
9ff15871556a4afc8f283a2fbc5d695d7531cd27 generated against B82169330.
Only ProductCore.local_draft_save gains two reason comments and method-local
#[allow(clippy::too_many_arguments)]. Parent explicitly authorized this single
ABI-preserving exception. No crate/module/global allowance or other lint waived.
Existing parameters/types/order, function body and generated contract unchanged;
this is NOT a parameter-reduction refactor and must remain disclosed in reports.

A typed record replacing the old positional method would change UniFFI checksums,
generated signatures and Host callers, requiring coordinated protocol migration.
The later fifth new method can use a typed record before its accepted generation;
that new source is not imported just to fix current strict gate.

Actual current-source results:
- FFI lib14PASS/0FAIL, exit0 (four-method API, not next fifth prepare method).
- FFI all-target strict Clippy -D warnings PASS, exit0, with this named exception.
- Build actual Rust cdylib + generate UniFFI Kotlin + cmp checked-in binding PASS.
  Four-method binding SHA256 remains65bd9238bba93e4ea17d233acd666128e81ecdde0489d4417d98801c54a616a9.
- Full workspace strict Clippy still FAIL101 only on core test
  document_edit_transactions.rs:387:11 needless_update (`..binding()` after all
  four fields already specified). Gateway/transaction original owner minimal
  removal pending; integrator has not changed that test or added suppression.

Raw commands/logs under evidence/*abi*.log. Current core test repeat_n fix had
fresh storage15PASS and per-target strict scan23/24PASS; transactions alone failed.
Previous full435 remains fixed67fd14c4, not a fresh full run ofc628e23e. Full
workspace gate/test and fixed-final-source review follow the remaining owner fix.
No fifth provider, candidate, hostverified/can_save release or paid/live request.
