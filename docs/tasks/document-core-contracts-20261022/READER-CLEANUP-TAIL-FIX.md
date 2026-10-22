# Cleanup-time authority regression

Original Reader: `ff3cc928311afc12bee3205f28b662c6b7499b34`.
Test-only reproduction: `7a72a8290f821eb015d34421e09c24ac9ca70cdc`.
Fixed behavior: `fdcdd48e8c85896be4310cc90e63046db65cb6cf`.

Parent's independent review identified that cleanup follows the prior final
grant check. A BEFORE DELETE reader-pin trigger setting grant expiry to zero
demonstrates a static path where one-shot or EOF delivery returned success after
authority became invalid. This also models elapsed storage wait crossing expiry.
Original source and logs remain immutable; no actual reproduction is claimed here.

Two separate regressions inject that real SQLite trigger. The one-shot fix
rechecks exact current metadata and original access after pin deletion within
the original transaction, without requiring the deleted pin. The EOF fix first
finishes explicit cleanup, then checks exact original document/grant in a fresh
transaction plus original monotonic idle/absolute deadlines before returning the
chunk. A cleanup error still withholds output, retains owned cleanup state and
poisons future registry reads/opens. Grant-only tail cannot authorize old heads.

Separate read-only reviewer confirmed the counterexample is statically closed
on fdcdd48e, including failure preservation and no deleted-pin requirement. Its
earlier review had missed this window; the new conclusion is not runtime proof.
Raw 04-before-fix and 05-fixed logs record NOT_RUN127 (cargo missing). Actual
RED/GREEN must run test-only 7a72 then fixed fdcdd in the Rust environment:
`cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib cleanup_time_revocation`.
No full-file hashing/performance behavior changed in this fix. The subsequent
performance slice must use a separate source SHA and retain this authority tail.
