# Independent review

Reviewer: isolated read-only agent independent_provider_review (fresh context).
Scope: new provider/tests, four local_draft_* bridges, plan and interfaces. Canonical
codec cross-checked from fixed host commit6d61baf709f6d5a1e411ec6f24a19f357dc9a8bc.
No high/medium severity defects identified. Three low findings were repaired:

1. Four bridge mutex failures used generic CORE_UNAVAILABLE rather than the fixed
   draft failure set. All now return local_draft_unavailable.
2. Project query storage failures were collapsed into local_draft_scope. Storage
   error variants now return local_draft_storage_unknown; regression test added.
3. Receipt tamper test left archive corrupt, masking receipt validation. Test now
   restores canonical archive before independently corrupting receipt_json.

Reviewer follow-up: all three repaired on static recheck; no new issue found.
git diff --check passed. Reviewer's separate Python checks confirmed exact DDL and
FFI fixture header/revision/length/checksum.

Limits: reviewer did not compile Rust, run Rust/FFI tests or generate UniFFI bindings;
cargo/rustc unavailable. Independent static review is not runtime acceptance.


## Actual Rust failure and repair re-review

The original static review missed the NULL CASE defect later found by actual Rust
verification (1 PASS/14 FAIL). That failure supersedes any implication of functional
acceptance. Original failure evidence is preserved unchanged. Follow-up independent
read-only review inspected the NULL/type/byte-bound repair and four regressions,
ran source-extracted SQL checks, and found an unbounded original receipt digest.
The same text/exact64-byte projection guard was added there and independently
rechecked; no outstanding static findings. Repaired-source Rust is still NOT_RUN.
See NULL-PROJECTION-FIX.md for scope, evidence and remaining HOLD conditions.
