# Independent static review

Reviewer: separate agent `/root/document_contract_review`, read-only, no source
modification, tool installation or runtime verification. Fixed production source:
`10d3aa83e2a93581107ad2e9f44331b5ea99d866`.

Conclusion: prior P2 issues, pagination issue and confounded tests are statically
closed; no new confirmed blocking issue found. Runtime acceptance remains NOT_RUN.

- blobs.rs:887–905: exact expected-digest retention; legacy unresolved uploads
  remain conservative; bounded 128-row keyset pagination and upload-ID length.
- candidate.rs:54: all returned SQL text columns bounded; pinned byte_length
  bounded in blobs.rs:457.
- candidate_tests.rs:145: exact StorageCorrupt assertion rather than a generic
  error that could be masked by the disabled publication gate.
- candidate_tests.rs:172–185: independent corrupt/restored/missing file and
  missing-pin checks.
- candidate.rs:151: post-seal lookup error remains Unknown; production publication
  stays disabled.

Nonblocking recommendations: add a traversal test spanning more than 128 uploads,
and use equal-length different-hash corruption. The latter is implemented in
`0ddb5d2a76ae42efcc7b252c86d2992a8a85c9f3`; the former remains an explicit test gap.
Static review does not replace compiling or executing either source.

Final reviewer follow-up on `0ddb5d2a76ae42efcc7b252c86d2992a8a85c9f3`:
only tests and module comments changed relative to 10d3aa83, with production logic
unchanged. candidate_tests.rs:176–179 preserves length, flips the first byte and
keeps the pin present, so it statically reaches hash-mismatch inspection. No new
issue found; static review passed. The >128-row test gap and Rust runtime HOLD
remain. Reviewer again performed no edits or execution.

## Pagination follow-up

Read-only fixed-source review of `02db15524dc4f3a1eccbd6571fe68c56e4ab62a7`:
new test design statically reasonable, no blocking issue or obvious type error,
production logic unchanged. candidate_tests.rs:118–170 constructs 160 committed
unresolved reservations ordered by actual upload IDs. Expected objects at
0/127/128/159 have no reference/pin masking retention; the latter two require
cross-page lookup. The unrelated orphan scans every reservation, without legacy
NULL-upload or pin interference. Sixth-project preparation, cross-scope rejection,
restart staging retention, unchanged journal/upload snapshots and second GC=0
assertions are reasonable. The missing >128-row test-source recommendation is
closed. Actual compilation/tests remain NOT_RUN and runtime acceptance HOLD.
Reviewer performed no source edits or execution.

## Worker and exact-format repair

Separate read-only review of `cab23b69b2aa56f55f3b44e0fe248f026da9c08d`
against 8802 found no new static blocker. business_worker.rs:19–23 includes the
full real documents module; its blobs/business/contract/sqlite dependencies are
already compiled into the worker. No stub or replacement retention policy exists.
Document tests remain cfg(test); candidate publication remains UnsupportedOperation.
Reviewer independently hashed all 13 fixed files: 13/13 match the independent
263dfe4 expected_sha256 values and owner evidence JSON. Worker is outside that
old file list and requires actual compilation/format verification. Static review
passed; no cargo/rustfmt was run and the original full-core compile blocker is
not declared closed until the Rust environment reruns the fixed source.
