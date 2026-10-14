# RD-P01 independent technical verification

Fixed SHA bb0c77cb83684e5e8e053465f463fe4d887d342c. Non-author reviewer
/root/device_deferred_rust_recovery. Isolated git archive
/tmp/rd-p01-independent-review-20261014, independent target
/tmp/rd-p01-independent-target. No author branch/worktree mutation, commit,
push, merge, installation, license acceptance, device/model or product action.

No blocking defect found within the declared provisional host-only scope.

1. Raw UTF-16 checks length before decoding, XML legality before trim/NFC,
   lone surrogate rejection, BOM/Unicode whitespace trim, NFC (not NFKC),
   nonempty and scalar count <=200 match the settled limited contract. Rust
   Unicode17 vs Dart Unicode8 remains explicit NOT_PROVEN globally.
2. Fresh --offline --locked cargo +1.99.0 test: exit0, 12/12. Two independent
   archive-only inverse mutations: removed raw guard fails raw_limit_before_trim;
   trim-before-XML fails xml_before_trim. Both cargo exit101/assertion failure;
   original source restored exact bytes and full 12-test suite exit0.
3. Fresh independent compiled Rust example plus unchanged archived Dart oracle:
   32 paired inputs exit0, 30 equal and 2 expected differences. Both differences
   are raw>2000 entryguard rejection vs old direct normalizer acceptance, justified
   by supplier-name-contract section2. They are NOT Unicode equality successes
   and do not promote fixture oracle or whole-scenario statuses. Driver adapted
   only fixed-blob git lookup and executable target path in temporary archive.
4. read_name checks synthetic scope+supplier ID then tombstone. edit_candidate
   reuses those checks, checks nonzero exact expected revision, validates complete
   raw, and rejects checked_add overflow. Borrowed immutable snapshot prevents
   mutation on all paths; existing tests confirm rejection preserves original.
   Same-name +1 is only a candidate, not an actual new-intent commit/receipt.
5. Fixed SHA diff paths stay wholly in RD-P01 experiment/task ownership; all
   archived fixed deliverable bytes still match Git blobs after mutation restore.

Remaining product gates: authenticated store/scope/current permissions, transactional
CAS/full selected identity and digest, canonical wire/digest/normalization version,
intent deduplication, real receipt/executor/persistence and Android actual load.
The candidate has no DB or side-effect path and cannot prove any of those gates.
Android actual load NOT_RUN; M03 blocked_contract. Eligible for bounded inclusion
as reversible experiment assets only, subject to root integration CI gate.

Commands: cargo +1.99.0 test --offline --locked --manifest-path
experiments/redesign/device-deferred/rust-domain/Cargo.toml; same toolchain build
--offline --locked --example normalize_probe; temporary independent mutations
runner /tmp/rd-p01-independent-review-mutations.py; temporary driver
experiments/redesign/device-deferred/rust-domain/tests/independent_differential.py.
All use CARGO_HOME/RUSTUP_HOME=/tmp/muyon-spike01-toolchain/{cargo,rustup}.
Detailed SHA/exit/log hashes: review.json; raw logs remain in this report directory.
