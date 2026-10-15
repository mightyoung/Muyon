# CORE AGENT offline wire protocol review

Base: `75981959070a4b8d6a6158dbb132e48eea8858fa`.
Production implementation: `b785e3d6c8ae3660f8661279cf28a8aa7cfdd544`.
Independent checker: `e19c6e1a3e874c73929cbbb921383bccfd977764`.
Mutation trace visibility: `50b3ccdee6b9bd2c94b78510a82a6ac04b3a63ed`.

## Scope and findings

The change is confined to the experimental core-agent lab, its dedicated workflow,
and task/review documents. It implements a single-choice, single-tool Chat
Completions SSE subset over a controlled local Python stdio service. It does not
establish real HTTP, model, native-device, or product-entry acceptance.

Non-author source reviews closed the original depth/native-pair/boundary findings.
The subsequent review identified stale usage after a failed turn, an escaped
private-history snapshot that could be saved but not reopened, incomplete earlier
history validation in the independent oracle, and the missing preterminal
physical-effect inverse control. The original owners fixed these findings;
the review retains the earlier immutable sources and failures as evidence.

The fixed source clears usage before exposing a new provider request, reads
private snapshots within the existing store limit without relaxing the wire
request limit, validates every native history pair against physical values and
original receipts, and checks preterminal zero-effect behavior using a compiling
inverse through the actual decoder and original Agent dispatch path.

## Verification and integration gate

Combination `46f49fbd0961959849198a7240b886672b93daf9` passed Core Agent CI
`38675888490`: 53 Rust tests, 26 original plus 18 wire process methods, 6 original
plus 7 wire harness methods, and 17 semantic inverse checks. The 45 raw matrix
entries are subcases, not 45 independent process methods. Earlier parser RED,
compile failure, and the invalid 50KB pipe-capacity assertion remain recorded.

The preterminal inverse changes two isolated mutant locations: it releases a real
decoder argument observation early, then pauses after a real persisted effect.
Its ACK timing is deliberately different from the baseline. A kill requires a
successful build, actual ACK, and the specified physical `1 != 0` assertion;
missing markers, timeouts, compile failures, or unrelated failures do not count.
The observation-only follow-up prints the original failure excerpt to CI output
because standard artifact download is unavailable in this environment.

Source review found no remaining Important in the fixed implementation. Integration
requires final non-author SPEC/QUALITY C0 and both required workflows succeeding
on the exact candidate. Only the authorized integration leader may perform a
normal develop merge. Main, author branches, and RED evidence must be retained;
postmerge acceptance requires both workflows on the exact merge commit.

## Evidence limits

Raw validation logs are outside the repository. Local Rust execution was not
available; Rust and actual subprocess evidence comes from the preinstalled,
offline GitHub runner. A nonreading helper proves a total deadline, while the
shared production writer's controlled WouldBlock test establishes blocked-write
guard coverage. Partial-argument cancellation is a Rust unit result; the process
checkpoint proves cancellation after complete arguments and before the terminal.
External SIGKILL cleanup is attributed to the harness, and crash-interval byte
counters can be measured lower bounds. These results do not claim M03 completion
or production provider readiness.
