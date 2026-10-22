# Independent review

Reviewer: separate evidence_review agent, no implementation edits, twice
independently executed tests using the installed toolchain.

Initial Important finding: derived Debug exposed LocalEvidence private cached
text without current permission. Author added negative test and reproduced
7 passed / 1 failed (debug-red.log), then implemented redacted Debug. Independent
retest passed 12/12 and confirmed no new Critical/Important findings. The
reviewer also requested more coverage of anchored requests, changed blob and
authority, citation order and mid-operation revocation; all were added.

Final supplement adds mid-operation revocation for open/find_literal/answer,
identity isolation across scope/document/revision and processing limits.
Final independent execution: exit 0, 15 passed, 0 failed. No unresolved
Critical/Important findings. Source identity canonical tuple encoding and all
three derived delivery revocation cases were explicitly checked.

Review boundaries: pure offline evidence processing only; no PDF engine,
persistent import receipts, Android/runtime integration or atomic host adapter
acceptance. These remain owner integration requirements in HANDOFF.md.

## Concrete store follow-up, fixed 3296cb8402afd5003279ad443d701dda1fee9f56

The independent reviewer executed real StoreEvidence tests against actual core
sources and persisted synthetic documents. Initial 9 passed. It flagged the
normal integration import as blocked by the intentionally unapplied owner export;
this remains production combination work, not a harness-derived completion claim.
Pure tests now reference actual local.rs so they remain independently executable.

A module split caused missing explicit imports in store.rs (21 compile errors).
The reviewer caught it; the author fixed imports, retained failure logs and reran
both store and full-core compilation. There is no unresolved source compile issue.

Final independent verification of the exact source commit: 12 passed, 0 failed,
exit 0. No unresolved Critical/Important source findings. Review confirmed final
owner transaction + persisted ReadText/current revision + actual reader lease,
wrong-format rejection, parser/registered-source separation, resource cleanup,
no business intent/index mutation and writer exclusion. No reviewer source edits.

Rust source manifest SHA256:
`9c7723e33eff57de884122c4c275dd00f39da8fa5e709f1118cb67fcea1e26c7`.
Runner SHA256:
`0ca6f7223a30d44adffb1a6d781b66064fbed7881f2af3cb75aa7ba0be5c6b19`.

Production export and Service/FFI calls remain parent B's known integration
blocker; static/real store review does not certify that an APK invokes this code.
