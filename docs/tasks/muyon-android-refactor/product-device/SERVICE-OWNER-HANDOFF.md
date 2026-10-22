# Close/rebind owner handoff

The e6a1f393 final-core run failed one of 13 methods: the first valid codec case
passed, then the second case's setup saw InvalidAuthority before entering its body.
Device logs show the first finished at 00:24:30.434, the second started at .435 and
failed at .443 in the same core PID 5303. The next recovery case killed that process,
so its later successes do not establish that the old owner naturally drained.

Production Service teardown was asynchronous while a successor could immediately
open the exclusively owned database. The fix registers a retirement latch and
stops accepting work synchronously in onDestroy. Each successor freezes its existing
predecessor latches during onCreate and waits only on those before opening native
storage on a background thread. Waiting on a dynamic set of later generations could
create a cycle during A -> B -> C recreation and is deliberately avoided.

Opening and closing share the old instance monitor. The latch is released only
after successful native close; close failure or a ten-second wait timeout remains
unavailable. No lock is cleared, database reset, write retried or test setup health
poll added. A new actual device regression performs eight immediate close/rebind
cycles, requires multiple owner epochs in one PID, and requires the first health
read after every Binder connection to succeed without retries.

Final validation: source `7b063cb4089fe21fdaf82657bcf00408e3f138b1`
passed all eight immediate close/rebind cycles on the API26 device, including
first-health success without retries and multiple epochs in one PID.
See [sealed core log](final/CORE.log) and [suite manifest](final/SUITE-MANIFEST.json).
The original failure remains in `E6A1-FINAL-CORE-FAIL.log`.
