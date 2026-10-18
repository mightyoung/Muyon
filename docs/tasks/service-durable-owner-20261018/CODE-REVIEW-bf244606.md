# Independent immutable code review

Reviewed source: `bf244606d162c4b60ee5b3073e53c4d367d8e24c`.
Execution location: `/workspace/Muyon`, selected execution environment, 2026-10-18.
Review input: `/tmp/durable-owner-review-bf244606.patch`, complete new production source, all 11 `DurableServiceHostOwnerTest` tests, `PLAN.md`, `DESIGN-REVIEW.md`, `IMPLEMENTER.md`, the existing callback adapter and generated immutable bridge records. No `AGENTS.md` was found by the workspace search. The supplied patch contains the implementation commit; full current test/source files were also read so that the tests-first parent was included.

## Dual conclusion

**Specification: changes required.** The bounded component scope is honestly described and is an acceptable prerequisite rather than an installed production owner. However, the persisted clock contract and fail-closed schema contract have the two Important defects below.

**Quality: changes required.** The authority guard, complete canonical tuple/budget encoding, conservative accounting and single SQLite commit are sound structural choices. The two defects need focused synthetic regression tests and fixes before this immutable source can be accepted. This review is static only; no build, test or runtime success is claimed. CI execution and its exact SHA remain root-owned evidence.

Paths below abbreviate `experiments/redesign/android-compose-lab/app/src/main/kotlin/com/mightyoung/muyon/androidlab/agentipc/DurableServiceHostOwner.kt` as **Owner** and the corresponding `src/androidTest/.../DurableServiceHostOwnerTest.kt` as **Test**.

## Findings

### Important I1 — A failed admission transaction discards the observed clock and expiry transition

**Evidence:** Owner lines 119–127 read time, write `high_water`, and expire held reservations within the same transaction as `block`. Lines 129–133 commit only after that block returns; an exception rolls back all these writes. Reserve's unique-request insertion at lines 162–169 can throw after the time/expiry update.

**Concrete static sequence on a fresh synthetic ledger:** reserve request `r` at time 100 with `holdMillis=10`, yielding expiry 110. At time 111, attempt another reserve for `r`. The transaction observes 111 and marks the original reservation expired, but the duplicate request constraint then throws; rollback restores the original held row and previous high-water 100. Set the clock to 105 and commit the original token: `105 >= 100`, expiry 110 is still in the future, all exact authority/proof checks still match, and the code can admit it. An expiry already observed by this component was resurrected after a failed operation and clock rollback.

**Required correction:** make the successful observation of high-water time and serialized expiry transition durable even when the subsequent admission work rolls back, while retaining atomic reservation/consumption/admission writes and the authority/SQLite lock protocol. Add a named synthetic test combining duplicate or injected write failure at/after expiry with rollback and reconstruction; assert the original hold stays expired or admission remains conservatively denied. The existing independent expiry test (Test 111–124) and trigger failure test (127–143) do not combine these conditions.

### Important I2 — Existing v1 databases with a different constraint schema are accepted

**Evidence:** Owner lines 82–88 accept user version 1, `quick_check=ok`, and readable column names. They do not establish the unique indexes, primary keys, checks, types or required schema definition created at lines 75–79. `quick_check` validates a database against its own schema; it does not prove that the expected constraints exist. Reserve lines 162–169 rely solely on `request_id UNIQUE` for durable duplicate rejection and perform no explicit duplicate lookup.

**Concrete static sequence on a new synthetic database:** provide all the expected v1 tables/columns, `clock_guard(1,0)`, and version 1, but omit `UNIQUE(request_id)` from `reservations`. It passes initialization. With the normal two-call fixture ceiling, reserve and commit the same request ID twice using two distinct generated tokens; both can be admitted. The component therefore does not fail closed for an unsupported same-version schema and loses its request one-shot contract.

**Required correction:** validate the exact supported schema/constraints before accepting an existing file (including indexes/constraint semantics; reject rather than repair). Add a fresh synthetic malformed-v1 fixture retaining column names but missing duplicate protection, and assert the owner remains unavailable and the file/schema is preserved. The existing schema test at Test 146–156 checks version 77 and corrupt bytes only.

### Minor M1 — Several specified edge cases are not established by the 11 tests

The normal reconstruction test (Test 40–53) reopens a held reservation, then consumes both calls without reopening consumed accounting. The contention test (95–108) exhausts calls, tokens and micros simultaneously, so it does not independently prove each quota dimension; it also has no competing commit/replay across connections. The expiry test uses 111 against expiry 110 rather than the exact boundary. No maximum signed-value round trip, unpaired-surrogate round trip, same-epoch authority refresh after consumed-ledger reconstruction, or OS cross-process lease test is present. The proof test does validate all four CallBudget fields, but field/flag changes across the full persisted binding are not exhaustively exercised. These are evidence limitations, not claims that those mechanisms are already broken. Prioritize the two Important regressions, then strengthen the cases used in handoff claims.

**Same repair-wave validation priorities:**

1. **Required to close I1/I2:** an at/after-expiry failing transaction followed by rollback and reconstruction cannot revive its token; malformed same-version constraint schemas deny without repair, including a fixture missing request-ID uniqueness. Preserve an independently atomic failed commit test.
2. **Required to claim the accepted design's minimum accounting/expiry coverage:** independently exhaust tokens and micros while calls remain available; reopen after consumption and refresh the same epoch without restoring quota; assert exact expiry `now == expires`; compete cross-connection duplicate/commit/replay attempts. These are targeted fresh-schema additions to the named test class, not authorization to broaden any suite.
3. **Recommended robustness evidence, deferrable if explicitly disclosed:** maximum signed-value and surrogate-string round trips, exhaustive binding-field mutation matrix, and a dedicated cross-process lock harness. Existing conservative conversions, complete encoder inspection and same-process authority-denial test provide partial evidence, but do not substitute for those runtime cases.

## Reviewed positive contracts and scope

- Authority `replace` and admission operations share the same guard; Owner 114–133 retains it through `endTransaction`. Reentrant authority operations are rejected (33–39). Scope collections are copied and made unmodifiable (30–32); generated provider/profile/budget records expose immutable fields. Proof/review functions are explicitly required to be pure and based on immutable guarded facts. This protocol still requires a trusted embedding authority; callbacks cannot prove that trust themselves.
- Complete binding, scope, payload, credential correlation, stored full budget and proof are checked before state consumption (174–195). Checked signed conversion and arithmetic prevent ordinary unsigned narrowing/overflow admissions. Held and consumed rows are counted within serialized transactions (142–160), with immutable epoch ceilings retained across object instances. Consumption and metadata admission share one transaction. No production hardcoded allow or send operation was found.
- Same-authority connections share a lease; concurrent different authority instances are rejected by identity and an OS file lock (241–254). The one-process authority deployment restriction is documented. The current test establishes same-process independent-authority denial only.
- Raw payloads and metadata remain plaintext indefinitely, and expired request tombstones are retained; this privacy/retention limitation is stated. Dedicated new-schema data is used; no old-state compatibility, migration, transport, production credential lookup or lifecycle installation is claimed.

No Critical findings were identified. Two Important findings and one Minor coverage limitation remain. Production approved authority, Application/Service installation, actual Rust prepare integration with this durable component, credential-handle source and future budget-enforcing transport remain explicit integration gates. ConfiguredChat remains unavailable; Auto/FullAllow and SyntheticLab behavior are outside this patch.

## Activity boundary and ownership release

Read-only code inspection only; no suites or tests were run, including no I04 or indirect containing suite. No old database, HTTP/model operation, credentials, remote write, merge, branch mutation, implementation change or extra agent was used. CI was not rerun. This report is the only file written by this reviewer. Findings are source-derived and have not been dynamically reproduced here. Review complete; report ownership released and writer stopped.
