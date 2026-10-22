# Verification record

## Immutable source and independent review

- Initial oracle SHA: `12ebe17f3a766da051f215ae25d383009a33a6ec`.
- Reviewed correction SHA: `43ddf7c328464f5e7b2e5752d02f7c582e44f30b`.
- Implementer: isolated `contract_tests` worker, experimental directory only.
- Independent reviewer: `fixed_sha_review`, read-only; reviewed each immutable SHA.
- Root reran the full experimental suite at the corrected SHA: 18 tests, 0 failures.

Initial review reproduced five gaps despite 13 passing tests: whitespace-only text,
4096-byte rather than 1024-byte deltas, overly narrow receipt IDs, completion without
projection, and displayed answer surviving invalidation. These were corrected with
new failing tests before implementation. Object reference schema_version=1 was also
added; it is not the database schema12 number.

Second independent review at `43ddf7c328464f5e7b2e5752d02f7c582e44f30b` found no
blocking issue for the **oracle deliverable** and reran 18/18 tests successfully.
It specifically confirmed clear-and-suspend on invalidation, no authorization on
reconnect, and the trusted-caller-only nature of reauthorize_display(). This is not
review or certification of Android integration or production authority.

## Results

| Check | Result | Evidence / reason |
| --- | --- | --- |
| Original test-first RED | EXPECTED_FAIL | `evidence/RED.log`: 13 tests, 10 assertion failures, 3 rejection tests already passed |
| Original GREEN | PASS | `evidence/GREEN.log`: 13/13 |
| Schema/strictness correction RED | EXPECTED_FAIL | `evidence/review-red.log`: 18 tests, 1 failure + 12 setup errors after adding required schema field |
| Correction RED after schema fix | EXPECTED_FAIL | `evidence/review-red-after-schema.log`: 18 tests, 6 failures + 1 missing-method error |
| Corrected experimental suite | PASS | `evidence/review-green.log`: 18/18; root and reviewer independently reran |
| Patch whitespace | PASS | `git diff --check` |
| Allowed path allocation | PASS | All changes under the two authorized new directories |
| Kotlin/Rust/full Flutter suites | NOT_RUN | Required executables absent; no broad HTTP-related host suite invoked |
| Android API26 Binder/native isolated-tool loop | NOT_RUN | Production edits awaiting B06 handoff; Android toolchain/device absent |
| Production business store/scope authority | NOT_RUN | Android adapter and host authority bridge absent |
| Live model/provider | NOT_RUN | No verified approved Service-owned profile/credential/budget binding |
| New contract CI | NOT_RUN | No workflow edits/dispatch authorized in this bounded phase |

Run from repository root:

```sh
python3 -B -m unittest discover -s experiments/redesign/frontend-service-loop-lab -v
git diff --check
```

Evidence paths in the table are relative to
`experiments/redesign/frontend-service-loop-lab/`. These are synthetic contract unit
tests only, not model calls, business DB reads, subprocess integration or device logs.

Full historical project tests were not run. No result here implies their success.
I04 was not retried or executed. No new platform approval rejection occurred; existing
production writes are **pending parent ownership transfer**, and historical I04 remains
**denied before execution / blocked**.
