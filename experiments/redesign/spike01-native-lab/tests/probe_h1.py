"""Actual foreign destructor reentry/paused release; run under an external timeout."""
import gc, sys, threading, weakref
import spike01_bridge_lab as bridge
from test_ffi import stimulus, typed
mode = sys.argv[1]
variant = sys.argv[2] if len(sys.argv)>2 else 'success'
session = bridge.LabSession()
ref = weakref.ref(session)
seen = []
replacement_seen = []
entered = threading.Event()
release = threading.Event()
class Replacement(bridge.LabObserver):
    def on_reply(self, digest): replacement_seen.append(digest)
class Observer(bridge.LabObserver):
    def on_reply(self, digest):
        ref().set_observer(Replacement())
        if variant == 'reject':
            raise bridge.LabCallbackError.Rejected('SYNTHETIC_AFTER_REPLACE')
        if variant == 'unexpected':
            raise ValueError('SYNTHETIC_FOREIGN_EXCEPTION')
    def __del__(self):
        print('destructor_enter', mode, variant, flush=True)
        try:
            getattr(ref(), mode)()
        except bridge.LabError.ReentrantClose:
            seen.append('reentrant_rejected')
        else:
            seen.append('unsafe_early_return')
        if variant == 'pause':
            entered.set()
            if not release.wait(3): seen.append('release_timeout')
        print('destructor_return', flush=True)
session.set_observer(Observer())
def run():
    try:
        session.run(typed(stimulus()))
    except bridge.LabError.CallbackRejected:
        assert variant in ('reject','unexpected')
        seen.append('callback_rejected')
if variant == 'pause':
    failures=[]; done=threading.Event()
    def bounded_run():
        try: run()
        except BaseException as e: failures.append(repr(e))
    worker=threading.Thread(target=bounded_run);worker.start()
    assert entered.wait(2)
    def close():
        try: getattr(ref(),mode)();done.set()
        except BaseException as e: failures.append(repr(e))
    closer=threading.Thread(target=close);closer.start()
    early=done.wait(.1)
    release.set();worker.join(2);closer.join(2)
    assert not early and done.is_set() and not worker.is_alive() and not closer.is_alive(), (early,seen)
    assert not failures,failures
else:
    run()
    # Only the replacement should remain: verify it can still deliver callbacks.
    session.run(typed(stimulus('新名字')))
    assert len(replacement_seen)==1,replacement_seen
gc.collect()
assert seen.count('reentrant_rejected')==1,seen
assert 'unsafe_early_return' not in seen and 'release_timeout' not in seen,seen
session.unsubscribe();session.close_session()
del session
gc.collect()
assert bridge.live_session_count()==0
print('H1_PASS',mode,variant,seen,flush=True)
