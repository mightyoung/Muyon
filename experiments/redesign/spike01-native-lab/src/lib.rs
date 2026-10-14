//! Throwaway SPIKE laboratory. No product schema, authority, DB or dispatch.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use unicode_normalization::UnicodeNormalization;
use std::sync::{Arc, Mutex, Condvar, atomic::{AtomicU64, AtomicUsize, Ordering}};
use std::cell::RefCell;

static LIVE_SESSIONS: AtomicUsize=AtomicUsize::new(0);
static NEXT_SESSION: AtomicU64=AtomicU64::new(1);
thread_local! { static CALLBACK_STACK:RefCell<Vec<u64>>=const { RefCell::new(Vec::new()) }; }

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum LabNormalization { Nfc }

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, uniffi::Record)]
#[serde(deny_unknown_fields)]
pub struct LabRequest {
    pub protocol: u32,
    pub raw_utf16: Vec<u16>,
    pub revision: u64,
    pub purpose: String,
    pub normalization: LabNormalization,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, uniffi::Record)]
pub struct LabReply {
    pub normalized_name: String,
    pub revision: u64,
    pub purpose: String,
    pub note: Option<String>,
    pub canonical_bytes: Vec<u8>,
    pub digest: String,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum LabError {
    #[error("invalid_argument:{reason}")]
    InvalidArgument { reason: String },
    #[error("protocol_unsupported")]
    ProtocolUnsupported,
    #[error("scope_denied")]
    ScopeDenied,
    #[error("closed")]
    Closed,
    #[error("reentrant_close")]
    ReentrantClose,
    #[error("callback_rejected")]
    CallbackRejected,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum LabCallbackError {
    #[error("callback_failure:{reason}")]
    Rejected { reason:String },
}
impl From<uniffi::UnexpectedUniFFICallbackError> for LabCallbackError {
    fn from(_:uniffi::UnexpectedUniFFICallbackError)->Self {
        Self::Rejected { reason:"FOREIGN_CALLBACK".into() }
    }
}

#[uniffi::export(rust, foreign)]
pub trait LabObserver: Send + Sync + std::fmt::Debug {
    fn on_reply(&self,digest:String)->Result<(),LabCallbackError>;
}

#[derive(uniffi::Object)]
pub struct LabSession { id:u64, state:Mutex<SessionState>, idle:Condvar }
struct SessionState { closed:bool, unsubscribing:bool, calls:usize, callbacks:usize, observer:Option<Arc<dyn LabObserver>> }

struct CallGuard<'a> { session:&'a LabSession, callback:bool }
impl Drop for CallGuard<'_> {
    fn drop(&mut self) {
        let mut state=self.session.state.lock().unwrap_or_else(|p|p.into_inner());
        state.calls-=1;if self.callback { state.callbacks-=1; }self.session.idle.notify_all();
    }
}
struct CallbackGuard { active:bool }
impl Drop for CallbackGuard { fn drop(&mut self) { if self.active { CALLBACK_STACK.with(|v|{v.borrow_mut().pop();}); } } }
// Rust drops fields in declaration order, including during unwinding. Foreign
// release may reenter this session: keep the TLS marker and counters alive until
// the last observer reference has been released. This also covers early errors
// before on_reply, not just successful callbacks.
struct ObservedCall<'a> {
    observer:Option<Arc<dyn LabObserver>>,
    _callback:CallbackGuard,
    _call:CallGuard<'a>,
}
impl Drop for LabSession { fn drop(&mut self) { LIVE_SESSIONS.fetch_sub(1,Ordering::SeqCst); } }

#[uniffi::export]
impl LabSession {
    #[uniffi::constructor]
    pub fn new()->Arc<Self> {
        LIVE_SESSIONS.fetch_add(1,Ordering::SeqCst);
        Arc::new(Self { id:NEXT_SESSION.fetch_add(1,Ordering::SeqCst),state:Mutex::new(SessionState {
            closed:false,unsubscribing:false,calls:0,callbacks:0,observer:None }),idle:Condvar::new() })
    }
    pub fn set_observer(&self,observer:Arc<dyn LabObserver>)->Result<(),LabError> {
        let mut s=self.state.lock().map_err(|_|bad("STATE_LOCK"))?;
        if s.closed { return Err(LabError::Closed); }
        if s.unsubscribing { return Err(bad("UNSUBSCRIBING")); }
        let previous=s.observer.replace(observer);drop(s);drop(previous);Ok(())
    }
    pub fn unsubscribe(&self)->Result<(),LabError> {
        if CALLBACK_STACK.with(|v|v.borrow().contains(&self.id)) { return Err(LabError::ReentrantClose); }
        let mut s=self.state.lock().map_err(|_|bad("STATE_LOCK"))?;
        s.unsubscribing=true;let previous=s.observer.take();
        while s.callbacks>0 { s=self.idle.wait(s).map_err(|_|bad("STATE_LOCK"))?; }
        s.unsubscribing=false;drop(s);drop(previous);Ok(())
    }
    pub fn close_session(&self)->Result<(),LabError> {
        if CALLBACK_STACK.with(|v|v.borrow().contains(&self.id)) { return Err(LabError::ReentrantClose); }
        let mut s=self.state.lock().map_err(|_|bad("STATE_LOCK"))?;
        s.closed=true;let previous=s.observer.take();
        while s.calls>0 { s=self.idle.wait(s).map_err(|_|bad("STATE_LOCK"))?; }
        drop(s);drop(previous);Ok(())
    }
    pub fn is_closed(&self)->bool { self.state.lock().map(|s|s.closed).unwrap_or(true) }
    pub fn run(&self,request:LabRequest)->Result<LabReply,LabError> {
        let mut s=self.state.lock().map_err(|_|bad("STATE_LOCK"))?;
        if s.closed { return Err(LabError::Closed); }
        let observer=s.observer.clone();s.calls+=1;if observer.is_some() { s.callbacks+=1; }drop(s);
        let active=observer.is_some();
        let call=CallGuard { session:self,callback:active };
        if active { CALLBACK_STACK.with(|v|v.borrow_mut().push(self.id)); }
        let observed=ObservedCall { observer,_callback:CallbackGuard { active },_call:call };
        let reply=evaluate_typed(request)?;
        if let Some(ref observer)=observed.observer {
            observer.on_reply(reply.digest.clone()).map_err(|_|LabError::CallbackRejected)?;
        }
        Ok(reply)
    }
}

#[uniffi::export]
pub fn live_session_count()->u64 { LIVE_SESSIONS.load(Ordering::SeqCst) as u64 }

#[uniffi::export]
pub fn evaluate_typed(request: LabRequest) -> Result<LabReply, LabError> {
    if request.protocol != 1 { return Err(LabError::ProtocolUnsupported); }
    if request.purpose != "spike01.name" { return Err(LabError::ScopeDenied); }
    if request.raw_utf16.len() > 2000 { return Err(bad("RAW_UTF16_LIMIT")); }
    if request.note.as_ref().is_some_and(|s| s.len() > 1024) { return Err(bad("NOTE_LIMIT")); }
    let decoded=String::from_utf16(&request.raw_utf16).map_err(|_|bad("UTF16"))?;
    if decoded.chars().any(|c| !matches!(c as u32, 0x9 | 0xa | 0xd | 0x20..=0xd7ff | 0xe000..=0xfffd | 0x10000..=0x10ffff)) {
        return Err(bad("XML_CHARACTER"));
    }
    let normalized_name:String=decoded.trim_matches(|c:char| c.is_whitespace() || c=='\u{feff}').nfc().collect();
    if normalized_name.is_empty() { return Err(bad("EMPTY")); }
    if normalized_name.chars().count()>200 { return Err(bad("NORMALIZED_LENGTH")); }
    #[derive(Serialize)]
    struct Business<'a> { normalized_name:&'a str, revision_decimal:String, purpose:&'a str, note:&'a Option<String> }
    let canonical_bytes=serde_json::to_vec(&Business { normalized_name:&normalized_name,
        revision_decimal:request.revision.to_string(),purpose:&request.purpose,note:&request.note }).map_err(|_|bad("CANONICAL"))?;
    let digest=Sha256::digest(&canonical_bytes).iter().map(|b|format!("{b:02x}")).collect();
    Ok(LabReply { normalized_name, revision:request.revision,purpose:request.purpose,note:request.note,canonical_bytes,digest })
}

fn bad(reason:&str)->LabError { LabError::InvalidArgument { reason:reason.into() } }

#[uniffi::export]
pub fn evaluate_json(bytes: Vec<u8>) -> Result<Vec<u8>, LabError> {
    if bytes.len()>32768 { return Err(bad("JSON_SIZE")); }
    let request:LabRequest=serde_json::from_slice(&bytes).map_err(|_|bad("JSON_SHAPE"))?;
    serde_json::to_vec(&evaluate_typed(request)?).map_err(|_|bad("CANONICAL"))
}

#[uniffi::export]
pub fn synthetic_panic() { panic!("SPIKE01_SYNTHETIC_PANIC"); }

#[uniffi::export]
pub fn unicode_table_version()->String {
    let (a,b,c)=unicode_normalization::UNICODE_VERSION;
    format!("{a}.{b}.{c}")
}

uniffi::setup_scaffolding!();

#[cfg(test)]
mod tests {
    use super::*;
    fn req(s: &str) -> LabRequest {
        LabRequest { protocol: 1, raw_utf16: s.encode_utf16().collect(), revision: 7,
            purpose: "spike01.name".into(), normalization: LabNormalization::Nfc, note: None }
    }
    #[test]
    fn observer_release_keeps_reentry_marker_on_real_rust_unwind() {
        use std::sync::Weak;
        struct PanicObserver { session:Weak<LabSession>, rejected:Arc<AtomicUsize> }
        impl std::fmt::Debug for PanicObserver {
            fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result { f.write_str("PanicObserver") }
        }
        impl LabObserver for PanicObserver {
            fn on_reply(&self,_:String)->Result<(),LabCallbackError> {
                self.session.upgrade().unwrap().set_observer(Arc::new(Quiet)).unwrap();
                panic!("SYNTHETIC_REAL_CALLBACK_UNWIND");
            }
        }
        impl Drop for PanicObserver {
            fn drop(&mut self) {
                let session=self.session.upgrade().unwrap();
                if matches!(session.close_session(),Err(LabError::ReentrantClose)) {
                    self.rejected.fetch_add(1,Ordering::SeqCst);
                }
                if matches!(session.unsubscribe(),Err(LabError::ReentrantClose)) {
                    self.rejected.fetch_add(1,Ordering::SeqCst);
                }
            }
        }
        #[derive(Debug)] struct Quiet;
        impl LabObserver for Quiet { fn on_reply(&self,_:String)->Result<(),LabCallbackError> { Ok(()) } }
        let baseline=live_session_count();let session=LabSession::new();
        let rejected=Arc::new(AtomicUsize::new(0));
        session.set_observer(Arc::new(PanicObserver { session:Arc::downgrade(&session),rejected:rejected.clone() })).unwrap();
        assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(||session.run(req("名字")))).is_err());
        assert_eq!(rejected.load(Ordering::SeqCst),2);
        session.run(req("新名字")).unwrap();session.unsubscribe().unwrap();session.close_session().unwrap();
        drop(session);assert_eq!(live_session_count(),baseline);
    }
    #[test]
    fn same_source_json_and_typed_produce_same_semantics_and_digest() {
        let r = req(" \u{feff}A\u{30a}公司 ");
        let typed = evaluate_typed(r.clone()).expect("normalization missing");
        assert_eq!(typed.normalized_name, "Å公司");
        let bytes = evaluate_json(serde_json::to_vec(&r).unwrap()).unwrap();
        let json: LabReply = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(typed, json);
        assert_eq!(typed.digest.len(), 64);
    }
    #[test]
    fn xml_validation_precedes_trim() {
        assert!(matches!(evaluate_typed(req("\u{0}名字")), Err(LabError::InvalidArgument { reason }) if reason == "XML_CHARACTER"));
    }
    #[test]
    fn raw_utf16_limit_precedes_normalization() {
        assert!(matches!(evaluate_typed(req(&" ".repeat(2001))), Err(LabError::InvalidArgument { reason }) if reason == "RAW_UTF16_LIMIT"));
    }
    #[test]
    fn invalid_surrogate_is_typed_error() {
        let mut r = req("x"); r.raw_utf16 = vec![0xd800];
        assert!(matches!(evaluate_typed(r), Err(LabError::InvalidArgument { reason }) if reason == "UTF16"));
    }
    #[test]
    fn nfc_codepoints_not_utf16_units_control_final_limit() {
        assert!(evaluate_typed(req(&"𠀀".repeat(200))).is_ok());
        assert!(matches!(evaluate_typed(req(&"𠀀".repeat(201))), Err(LabError::InvalidArgument { reason }) if reason == "NORMALIZED_LENGTH"));
    }
    #[test]
    fn protocol_and_purpose_are_not_ignored() {
        let mut r=req("名字");r.protocol=2;assert!(matches!(evaluate_typed(r),Err(LabError::ProtocolUnsupported)));
        let mut r=req("名字");r.purpose="arbitrary".into();assert!(matches!(evaluate_typed(r),Err(LabError::ScopeDenied)));
    }
    #[test]
    fn json_unknown_security_field_is_rejected() {
        let mut v=serde_json::to_value(req("名字")).unwrap();v["capability"]=serde_json::json!("synthetic");
        assert!(matches!(evaluate_json(serde_json::to_vec(&v).unwrap()),Err(LabError::InvalidArgument{reason}) if reason=="JSON_SHAPE"));
    }
    #[test]
    fn json_missing_and_null_note_follow_explicit_lab_policy() {
        let mut v=serde_json::to_value(req("名字")).unwrap();v.as_object_mut().unwrap().remove("note");
        let missing=evaluate_json(serde_json::to_vec(&v).unwrap()).unwrap();v["note"]=serde_json::Value::Null;
        assert_eq!(missing,evaluate_json(serde_json::to_vec(&v).unwrap()).unwrap());
    }
    #[test]
    fn json_fraction_and_overflow_revision_are_rejected() {
        for value in [serde_json::json!(1.5),serde_json::json!(-1),serde_json::json!("18446744073709551616")] {
            let mut v=serde_json::to_value(req("名字")).unwrap();v["revision"]=value;
            assert!(matches!(evaluate_json(serde_json::to_vec(&v).unwrap()),Err(LabError::InvalidArgument{reason}) if reason=="JSON_SHAPE"));
        }
        let text=String::from_utf8(serde_json::to_vec(&req("名字")).unwrap()).unwrap().replace("\"revision\":7", "\"revision\":18446744073709551616");
        assert!(matches!(evaluate_json(text.into_bytes()),Err(LabError::InvalidArgument{reason}) if reason=="JSON_SHAPE"));
    }
    #[test]
    fn json_unknown_enum_is_rejected() {
        let mut v=serde_json::to_value(req("名字")).unwrap();v["normalization"]=serde_json::json!("unknown_security_mode");
        assert!(matches!(evaluate_json(serde_json::to_vec(&v).unwrap()),Err(LabError::InvalidArgument{reason}) if reason=="JSON_SHAPE"));
    }
    #[test]
    fn panic_probe_really_panics_inside_rust() {
        assert!(std::panic::catch_unwind(synthetic_panic).is_err());
    }
    #[derive(Debug)]
    struct Counter { seen:AtomicUsize }
    impl LabObserver for Counter {
        fn on_reply(&self,_digest:String)->Result<(),LabCallbackError> { self.seen.fetch_add(1,Ordering::SeqCst);Ok(()) }
    }
    #[test]
    fn observer_runs_then_unsubscribe_releases_and_stops_callbacks() {
        let s=LabSession::new();let o=Arc::new(Counter {seen:AtomicUsize::new(0)});
        s.set_observer(o.clone()).unwrap();assert_eq!(Arc::strong_count(&o),2);
        s.run(req("名字")).unwrap();assert_eq!(o.seen.load(Ordering::SeqCst),1);
        s.unsubscribe().unwrap();assert_eq!(Arc::strong_count(&o),1);
        s.run(req("新名字")).unwrap();assert_eq!(o.seen.load(Ordering::SeqCst),1);
    }
    #[test]
    fn explicit_close_rejects_calls_and_native_drop_balances_count() {
        let before=live_session_count();let s=LabSession::new();assert_eq!(live_session_count(),before+1);
        s.close_session().unwrap();assert!(matches!(s.run(req("名字")),Err(LabError::Closed)));
        drop(s);assert_eq!(live_session_count(),before);
    }
    #[derive(Debug)]
    struct Rejector;
    impl LabObserver for Rejector {
        fn on_reply(&self,_digest:String)->Result<(),LabCallbackError> { Err(LabCallbackError::Rejected{reason:"SYNTHETIC".into()}) }
    }
    #[test]
    fn foreign_callback_error_becomes_typed_lab_error() {
        let s=LabSession::new();s.set_observer(Arc::new(Rejector)).unwrap();
        assert!(matches!(s.run(req("名字")),Err(LabError::CallbackRejected)));
    }
    #[derive(Debug)]
    struct Blocker { entered:std::sync::mpsc::Sender<()>, release:std::sync::Mutex<std::sync::mpsc::Receiver<()>> }
    impl LabObserver for Blocker {
        fn on_reply(&self,_digest:String)->Result<(),LabCallbackError> {
            self.entered.send(()).unwrap();self.release.lock().unwrap().recv().unwrap();Ok(())
        }
    }
    #[test]
    fn close_waits_for_actual_inflight_callback() {
        use std::{sync::mpsc,thread,time::{Duration,Instant}};
        let s=LabSession::new();let (entered_tx,entered_rx)=mpsc::channel();let (release_tx,release_rx)=mpsc::channel();
        s.set_observer(Arc::new(Blocker{entered:entered_tx,release:std::sync::Mutex::new(release_rx)})).unwrap();
        let (result_tx,result_rx)=mpsc::channel();let runner=s.clone();
        let run_thread=thread::spawn(move|| { result_tx.send(runner.run(req("名字"))).unwrap(); });
        entered_rx.recv_timeout(Duration::from_millis(500)).expect("callback not executed");
        let (done_tx,done_rx)=mpsc::channel();let closer=s.clone();
        let close_thread=thread::spawn(move|| { done_tx.send(closer.close_session()).unwrap(); });
        let until=Instant::now()+Duration::from_millis(500);
        while !s.is_closed() && Instant::now()<until { thread::yield_now(); }
        let marked_closed=s.is_closed();let completed_early=done_rx.try_recv().is_ok();
        release_tx.send(()).unwrap();
        assert!(marked_closed,"close did not fence new calls");assert!(!completed_early,"close returned before callback ended");
        done_rx.recv_timeout(Duration::from_secs(1)).unwrap().unwrap();result_rx.recv_timeout(Duration::from_secs(1)).unwrap().unwrap();
        run_thread.join().unwrap();close_thread.join().unwrap();
    }
    #[derive(Debug)]
    struct Reentrant { session:std::sync::Weak<LabSession>, rejected:std::sync::atomic::AtomicBool }
    impl LabObserver for Reentrant {
        fn on_reply(&self,_digest:String)->Result<(),LabCallbackError> {
            self.rejected.store(matches!(self.session.upgrade().unwrap().close_session(),Err(LabError::ReentrantClose)),Ordering::SeqCst);Ok(())
        }
    }
    #[test]
    fn callback_reentrant_close_rejects_instead_of_self_deadlock() {
        let s=LabSession::new();let o=Arc::new(Reentrant{session:Arc::downgrade(&s),rejected:std::sync::atomic::AtomicBool::new(false)});
        s.set_observer(o.clone()).unwrap();s.run(req("名字")).unwrap();assert!(o.rejected.load(Ordering::SeqCst));
        assert!(!s.is_closed());s.close_session().unwrap();
    }
}
