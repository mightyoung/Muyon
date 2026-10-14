"""Real generated Python -> Rust .so probe; no product or Android acceptance."""
import gc
import hashlib
import json
import threading
import time
import unittest
import weakref
import spike01_bridge_lab as bridge


def units(text):
    raw=text.encode('utf-16-le','surrogatepass')
    return [int.from_bytes(raw[i:i+2],'little') for i in range(0,len(raw),2)]


def stimulus(text='名字',revision=7,note=None):
    return {'protocol':1,'raw_utf16':units(text),'revision':revision,'purpose':'spike01.name','normalization':'nfc','note':note}


def typed(value):
    return bridge.LabRequest(**{**value,'normalization':bridge.LabNormalization.NFC})


class Counter(bridge.LabObserver):
    def __init__(self): self.seen=[]
    def on_reply(self,digest): self.seen.append(digest)


class FfiProbe(unittest.TestCase):
    def test_valid_pair_semantics_canonical_bytes_and_digest(self):
        for text in [' A\u030a公司 ','\ufeff名字\ufeff','名字\t内部','é','e\u0301','𠀀'*200,'\u180e名字\u180e']:
            for revision in [0,2**53+1,2**64-1]:
                value=stimulus(text,revision)
                actual=bridge.evaluate_typed(typed(value))
                other=json.loads(bridge.evaluate_json(json.dumps(value,ensure_ascii=True).encode()))
                self.assertEqual(actual.normalized_name,other['normalized_name'])
                self.assertEqual(actual.revision,other['revision'])
                self.assertEqual(actual.canonical_bytes,bytes(other['canonical_bytes']))
                self.assertEqual(actual.digest,other['digest'])
                self.assertEqual(actual.digest,hashlib.sha256(actual.canonical_bytes).hexdigest())

    def test_invalid_domain_inputs_same_typed_error_on_both_paths(self):
        for text,reason in [('\x00名字','XML_CHARACTER'),('\ud800','UTF16'),(' '*2001,'RAW_UTF16_LIMIT'),('𠀀'*201,'NORMALIZED_LENGTH'),('  ','EMPTY')]:
            value=stimulus(text)
            for call in [lambda:bridge.evaluate_typed(typed(value)),lambda:bridge.evaluate_json(json.dumps(value).encode())]:
                with self.assertRaises(bridge.LabError.InvalidArgument) as error:call()
                self.assertEqual(error.exception.reason,reason)

    def test_unknown_json_field_enum_and_numeric_shapes_reject(self):
        for change in [{'capability':'synthetic'},{'normalization':'unknown'},{'revision':False},{'revision':1.5},{'revision':-1},{'raw_utf16':None}]:
            with self.assertRaises(bridge.LabError.InvalidArgument) as error:
                bridge.evaluate_json(json.dumps({**stimulus(),**change}).encode())
            self.assertEqual(error.exception.reason,'JSON_SHAPE')
        with self.assertRaises(TypeError):
            bridge.LabRequest(**{**stimulus(),'normalization':bridge.LabNormalization.NFC,'capability':'synthetic'})

    def test_missing_null_note_policy_is_explicit(self):
        value=stimulus();value.pop('note')
        missing=bridge.evaluate_json(json.dumps(value).encode());value['note']=None
        self.assertEqual(missing,bridge.evaluate_json(json.dumps(value).encode()))

    def test_protocol_and_purpose_typed_errors(self):
        for change,error in [({'protocol':2},bridge.LabError.ProtocolUnsupported),({'purpose':'arbitrary'},bridge.LabError.ScopeDenied)]:
            value={**stimulus(),**change}
            for call in [lambda:bridge.evaluate_typed(typed(value)),lambda:bridge.evaluate_json(json.dumps(value).encode())]:
                with self.assertRaises(error):call()

    def test_panic_is_caught_at_actual_uniffi_boundary(self):
        with self.assertRaises(bridge.InternalError):bridge.synthetic_panic()
        self.assertEqual(bridge.evaluate_typed(typed(stimulus())).normalized_name,'名字')

    def test_actual_foreign_callback_unsubscribe_and_gc_release(self):
        baseline=bridge.live_session_count();session=bridge.LabSession();observer=Counter();ref=weakref.ref(observer)
        session.set_observer(observer);del observer;gc.collect()
        self.assertIsNotNone(ref())
        session.run(typed(stimulus()));self.assertEqual(len(ref().seen),1)
        session.unsubscribe();gc.collect();self.assertIsNone(ref())
        session.run(typed(stimulus('新名字')))
        session.close_session()
        with self.assertRaises(bridge.LabError.Closed):session.run(typed(stimulus()))
        del session;gc.collect();self.assertEqual(bridge.live_session_count(),baseline)

    def test_actual_foreign_error_mapping(self):
        class Rejector(bridge.LabObserver):
            def on_reply(self,digest):raise bridge.LabCallbackError.Rejected('SYNTHETIC')
        class Unexpected(bridge.LabObserver):
            def on_reply(self,digest):raise ValueError('SYNTHETIC_UNEXPECTED')
        for observer in [Rejector(),Unexpected()]:
            session=bridge.LabSession();session.set_observer(observer)
            with self.assertRaises(bridge.LabError.CallbackRejected):session.run(typed(stimulus()))
            session.close_session();del session
        gc.collect()

    def test_actual_close_waits_for_inflight_foreign_callback(self):
        entered=threading.Event();release=threading.Event();done=threading.Event();errors=[]
        class Blocker(bridge.LabObserver):
            def on_reply(self,digest):
                entered.set()
                if not release.wait(2):raise bridge.LabCallbackError.Rejected('TIMEOUT')
        session=bridge.LabSession();session.set_observer(Blocker())
        def run():
            try:session.run(typed(stimulus()))
            except Exception as e:errors.append(type(e).__name__)
        def close():
            try:session.close_session();done.set()
            except Exception as e:errors.append(type(e).__name__)
        runner=threading.Thread(target=run);runner.start();self.assertTrue(entered.wait(1))
        closer=threading.Thread(target=close);closer.start()
        until=time.monotonic()+1
        while not session.is_closed() and time.monotonic()<until:time.sleep(.001)
        marked_closed=session.is_closed();early=done.is_set();release.set()
        runner.join(2);closer.join(2)
        self.assertTrue(marked_closed);self.assertFalse(early);self.assertTrue(done.is_set())
        self.assertFalse(runner.is_alive());self.assertFalse(closer.is_alive());self.assertEqual(errors,[])
        del session;gc.collect()

    def test_actual_reentrant_callback_close_rejects(self):
        session=bridge.LabSession();seen=[];ref=weakref.ref(session)
        class Reentrant(bridge.LabObserver):
            def on_reply(self,digest):
                try:ref().close_session()
                except bridge.LabError.ReentrantClose:seen.append('rejected')
        session.set_observer(Reentrant());session.run(typed(stimulus()))
        self.assertEqual(seen,['rejected']);self.assertFalse(session.is_closed())
        session.close_session();del session;gc.collect()


if __name__=='__main__':unittest.main()
