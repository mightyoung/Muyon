# AUTH-1b TLS extension independent review and repair

Independent reviewer /root/auth_b2_foundation_review inspected all six changed files at fixed b3a7de48bcf99ffd514e0b03cca0ca6cf663d818, base 304da36c00ebd22ee8be81da91d26bc83a5dc177, in isolated /tmp/auth1b-tls-review. Original recommendation: do not accept the TLS extension until both blocking findings below are repaired and independently rechecked. The ordinary strict analyzer and +11 transfer tests passed, but two additional real paired TLS drivers failed behavior assertions. No compile failures were counted as findings. B3/C or production wiring remain separate pending scope.

## Actual peer certificate was not bound to the capability

Producer bound cached peer A id/fingerprint; send checked only URI/body and could use actual, already-paired peer B at the same address/port. The independent test retained cached A, closed its receiver, started paired B at the same URI, then sent using the real probe result B. B received the exact body while the ledger remained associated with A's review. No forged LanPeer was required.

Repair: HostAuthorizationLink retains the host intent endpoint identity and validates the actual transport identity. TransferService.send binds the id/fingerprint used by TLS pinning, and rechecks the current live id/address/port/fingerprint and pairing. The formal regression assistant_transfer_peer_identity_test.dart rejects B with zero transport rows and an empty B inbox. Author reproduced a valid RED before repair.

## Byte-boundary authority depended on an optional caller callback

A caller could pass authorization without checkBeforeEffect. After ledger entry, connection and stream guards then had no capability recheck. Independent real TLS test advanced the injected registry clock at onProgress(sent=0), after connection but before bytes, beyond the two-minute approval deadline. The old implementation still sent the full body successfully.

Repair: TransferService.send always creates its own guard incorporating capability identity/current authority and pairing; it combines any caller callback and passes the mandatory guard through freeze, ledger wait, connection and chunk boundaries. The formal regression assistant_transfer_capability_boundary_test.dart deliberately omits the caller callback, advances the real clock at the connection boundary and asserts failed ledger state, bytes_sent=0, exact review association and empty inbox.

## Verification boundary

Author focused helper + transfer normal paths + both independent regressions: +36 passed. Isolated mutants dropping the actual-certificate comparison and mandatory live capability recheck each fail their respective behavior regression; snapshot files restored byte-for-byte. Raw drivers and logs remain /tmp. Restored strict/full and independent fixed-commit re-review evidence will be appended only after completion. The original b3a7de4 review is not retroactively described as passing.

Restored repair snapshot: strict `No issues found! (ran in 4.8s)`; full host +1009 ~3 passed. The only changes after full execution were removal of unnecessary test imports and addition of required braces, with assertions unchanged. Both new regressions and exact production files match the restored snapshot; B3 WIP was excluded from this snapshot and checkpoint.
