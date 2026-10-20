# Commit observed before client callback loss

`ProductUnknownRecoveryTest` uses a real P04 ProductClient and real Service/native
store. Before sending, it persists the same original-intent journal used by the
supplier screen. It holds only the test's main looper while an independent
read-only platform SQLite connection observes the actual committed receipt.
It then closes the sending client before its callback can run, asserts the real
client's unknown/query_original outcome, and kills the private Service process.

After recreating the actual MainActivity, the test requires no pre-existing success
receipt, clicks the real query-original control, and compares the recovered receipt
to the independently observed original. Supplier revision and history count must
remain one. There is no model, socket, synthetic store, fabricated success callback,
production hook, database reset or automatic replay.

Boundary: the protocol test explicitly journals and sends through its own real
client; it does not claim the original confirm button itself was clicked while
the looper was held. Existing separate UI tests cover the visible confirm action.
The loss is of callback delivery to the client, including an already queued Binder
reply; it does not assert that the Service had never sent a reply on Binder.
This is a business-only SQLite recovery test, unrelated to the held I04 legacy HTTP
experiment. Device validation is pending the next fixed candidate.
