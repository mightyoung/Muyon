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
