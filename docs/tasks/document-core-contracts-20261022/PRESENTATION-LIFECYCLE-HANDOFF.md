# Presentation lifecycle fixed-source handoff

Interface-first: `37e1f0d80a085bb6f8ed69c93c8c8e5093086dce`.
Final source: `ee184fc1dd90faf2c3cdd48d735f47274de6d418`.
Original implementation: `26afe87b583637caa62e59c567adb2f44d47e173`.
Review fix: `7ef66355af8cdabc397b8657551092f11bc3c122`.
Branch: task/document-core-contracts-20261022.

## Ready for the sole FFI owner to consume

PRESENTATION-LIFECYCLE-INTERFACE.md gives exact additive signatures and Host
execution rules. The real new mode requires Render and an exact saved
DocumentAccess. EOF retains the same actual pin, original authority/revision,
snapshot and native session, without regrant/reopen. The public serialized ticket
has no constructor/Deserialize; its native generation fences async page callbacks.
Status exposes Loading versus fully transferred Ready and remaining time bounded
by original grant expiry, original15s idle and original30s absolute deadlines.

check is a refresh of authorization facts, not a lease renewal; it reuses the
authenticated snapshot and actual current head/grant/pin/stamp without a full
source hash. Explicit Ready frame advance increments generation, updates ordinary
idle activity only, and keeps absolute/grant deadlines. One presentation selection
is active per host; explicit replacement closes old presentation before opening
the requested exact reference, including same-document reopen with a distinct ID.

Legacy transport still releases at EOF. Legacy read_chunk/is_current/close cannot
bypass presentation ticket generation. Internal cleanup handles expiry and
replacement; trusted administrative close_all remains available for logout/owner
shutdown and failed-cleanup retry. Failure sets terminal inactive state, poisons
reads/opens and retains the actual native snapshot/pin budget until cleanup succeeds.

Host invalidation notifications have an eight-item bound; overflow or poisoning
sets clear_all. Host must take these notifications after native operations and
clear PFD/bitmap/private cache on denial, terminal event, deadline, background or
scope/actor change. Status timers must be anchored to request start to avoid
extending deadlines through IPC/queue latency. Old callback generations may never
be upgraded to current tickets. These are cooperative trusted-host obligations,
not a claim to revoke an OS PFD instantly without Host execution.

The canonical grant validator now has an internal deadline-returning helper;
the old unit-result wrapper and all checks remain. Internal presentation deadline
projection calls exact current-head validation and the same grant checker; it
does not duplicate policy, create a grant, accept a path, widen transaction helper
visibility or derive current from latest. No schema migration was needed.

Native snapshot payload remains64MiB total,30MiB/source,8 sessions; EOF and frame
advance reuse that same allocation and pin. Host external cache adds its own
<=source-length/30MiB budget and must be cleared independently. No PDF page count,
coordinates, parsing/rendering success or native-format fidelity is invented.

## Explicit downstream patch requirement

FFI466424b13400c3f88b0cfec815ce3450c41b3cff document_bridge.rs:271 removes mapping
at EOF and :273 sets session_active=!eof. The sole FFI owner must add an explicit
presentation mode retaining the native ticket/mapping at EOF, route its chunk and
status/frame/close operations to the new ticket APIs, compare incoming generation
against the stored native ticket and forward terminal notifications/time bounds.
Its old raw mode keeps current semantics. Merely retaining core state cannot fix
that existing FFI adapter. This owner did not modify FFI/lib.rs/Android or create
a PFD/cache. Android presentation is therefore not yet accepted as a product flow.

## Test-first history and independent review

Ten original synthetic presentation tests were authored before/with minimal
implementation fixes. They cover same-pin/snapshot EOF retention, raw compatibility,
stale page generations including legacy bypass attempts, grant active/generation/
epoch/expiry/project deletion after EOF, selection/scope and old handle fencing,
old head after EOF with no latest substitution, idle/absolute expiry and resources,
short actual grant deadline/no renewal, cleanup failure/poison/retry and bounded
notification overflow. Existing Reader17 and all prior contract tests remain.

Independent review of26afe found P2: legacy close/is_current could bypass ticket
generation. The test-first02 log retains the reproduction attempt; source7ef66355
made these legacy entries reject presentation and moved internal cleanup private.
Final review ofee184fc1 confirmed P2 statically closed, checked short-grant expiry
unchanged, and found no new confirmed blocker or obvious type/borrow error.

Raw attempts in presentation-evidence/01,02,03: targeted presentation tests,
complete core and owned rustfmt are all **NOT_RUN127** (cargo/rustfmt unavailable).
`git diff --check` exited0. There is no actual new RED/GREEN claim. Fixed-source
Rust compilation, old/new full regression, formatter and downstream FFI/Host
acceptance remain pending. Actual hardware lifetime and lifecycle callbacks were
not run, and no source/clock/permission limit was weakened to fabricate a pass.

## Prior actual evidence stays separate

Parent delivered immutable f38ec13b3ec75b27294e1af196e1ccd7b52d5939: pure-tail
fec40 six probes+15/core270 passed; snapshot2e713 six probes+17/core274 and actual
cost counters passed (30MiB open90MiB hashing,480 chunks0 whole-source hashing;
third30MiB budget refused). Counts overlap and are not summed. Its pure snapshot
formatter97969f9ab6728e8022b3ff7b7a069a655e94c9d8 was cleanly cherry-picked as
838c01aae735e0845f170d962bd8653e60c7e9fb before this feature, preserving behavior.
Neither the old runtime nor format pass verifies new presentation source.

B's independent lint-only7557cc9f and report3f73863d remain on their own B-baseline
branch; they were not imported here. Artifacts source resolver0e85c6e9 request has
been read; its transaction-invalidation wiring is the next separate slice, not
included or claimed complete here. No real engine/model/search, user file, external
message, paid action, credential/permission change, main/develop merge or deployment.
