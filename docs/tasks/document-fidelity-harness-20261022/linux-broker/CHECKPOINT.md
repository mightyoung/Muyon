# Concrete Linux source checkpoint

Base98dadd88beeec552bff6efbef5325efbeeae04c3. First immutable slice is bounded inherited-FD IPC and safe snapshot primitives, tests and raw logs. It does not yet include the rest of the in-progress Linux backend/worker wiring; the following source commit will freeze that separately for independent review.

Implemented in this slice: actual Unix stream send/recv loops with kernel SCM_CREDENTIALS, bounded canonical frames, nonce/request/sequence binding, duplicate-key/nonfinite/EOF/timeout/oversize/replay rejection; actual socketpair partial I/O tests. Snapshot NativeFiles uses dirfd/openat O_NOFOLLOW/O_NONBLOCK, fixed basename, regular+single-link+size checks, bounded reads, exact output set, immutable pre/post inode/size/time metadata and reaped prerequisite; syscall tests use FakeFiles only, no real file fixture changed.

Commands executed now:
- python3 -m unittest tools.document_fidelity.adapters.runner.linux.tests.test_primitives -v:6 PASS exit0, primitives-checkpoint.log.
- python3 -m unittest discover -s tools/document_fidelity/adapters/runner/linux/tests -v:17 PASS exit0 on current in-progress working tree, linux-first-complete.log (not a claim all17 source belongs to this first slice).
- python3 -m unittest discover -s tools/document_fidelity/adapters/runner/tests -v:28 PASS exit0, runner-checkpoint.log.
- python3 -m unittest discover -s tools/document_fidelity/tests -v:60 PASS exit0, legacy-checkpoint.log.

Raw initial missing-module RED, parse-status structured-error failure, relative-import and unavailable Python fcntl-symbol failures remain in evidence. Numeric Linux UAPI seal constants were verified read-only from /usr/include/linux/fcntl.h; no native seal syscall was run. No tool/dependency blocker for current source/unit work; no software install. Remaining concrete kernel/backend/session/bootstrap source is in progress with fake syscalls, default production HOLD.

No namespace, sandbox, worker CLI or third-party engine launch/import occurred. Known bwrap UID-map read-only refusal was not retried/worked around. Current true resources/image/provenance/license/scope and runtime qualification are absent; real native paths NOT_RUN. This checkpoint does not claim backend qualification or final review completion.
