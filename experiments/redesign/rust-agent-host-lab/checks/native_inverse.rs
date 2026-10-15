// Compiled only in a private copy as tests/native_inverse.rs. Existing physical
// scope/pre-handler oracles are included unchanged; one new oracle isolates the
// final of three model-payload admissions rather than disabling all checks.
include!("native_read.rs");

struct FinalSendReview {
    authority: Rc<Authority>,
    projection_reviews: Rc<std::cell::Cell<usize>>,
}
impl PurposeReview for FinalSendReview {
    fn review(&self, value: &Json, facts: &Json, purpose: &str) -> Result<()> {
        if purpose == "model_payload" && value.encode().contains("synthetic drill") {
            let count = self.projection_reviews.get() + 1;
            self.projection_reviews.set(count);
            if count == 3 {
                self.authority.0.borrow_mut().model_allowed = false;
            }
        }
        Review.review(value, facts, purpose)
    }
    fn mask_answer(&self, text: &str) -> Result<String> {
        Review.mask_answer(text)
    }
}
#[test]
fn final_native_send_admission_rechecks_after_policy() {
    let auth = authority();
    let count = Rc::new(std::cell::Cell::new(0));
    let plugin = PathBuf::from(std::env::var("MUYON_PLUGIN_CONTRACT_BIN").unwrap());
    let s = NativeSession::create(
        &directory(), &plugin, auth.clone(),
        Rc::new(FinalSendReview { authority: auth, projection_reviews: count.clone() }),
        "inspect selected equipment",
    ).unwrap();
    s.borrow_mut().register(Enrollment {
        bundle: json(include_str!("../../../plugin-contract-lab/fixtures/equipment_loan.json")),
        operation: "equipment_loan/inspect_equipment@1".into(),
        tool_id: "equipment_loan.inspect_equipment".into(),
        binding_id: "host-equipment-read".into(),
        scope_refs: equipment_scope(),
        handler: Box::new(|_: &Json| Ok(RawRead { raw: projection(), projection: projection() })),
    }).unwrap();
    let (mut provider, sent) = gateway(&s);
    let mut a = agent(&s);
    a.run_with_runtime_ports(&mut provider, &mut RuntimePorts { session: s.clone() }, &Hooks::default()).unwrap();
    assert_eq!(count.get(), 3, "NATIVE_FINAL_SEND_REACH: all three second-turn payload reviews must run");
    assert_eq!(s.borrow().handler_calls, 1, "NATIVE_FINAL_SEND_REACH: actual read required");
    assert_eq!(s.borrow().store.receipt_count(), 1, "NATIVE_FINAL_SEND_REACH: original receipt required");
    eprintln!("NATIVE_FINAL_SEND_REACHED reviews=3 reads=1 receipts=1");
    assert_eq!(sent.borrow().len(), 1, "NATIVE_FINAL_SEND_BOUNDARY: post-policy revoke must deny second endpoint bytes");
    assert_ne!(a.state.status, "completed");
}

#[test]
fn selected_scope_denies_before_dispatch_facts() {
    for permitted in [true, false] {
        let auth = authority();
        if !permitted {
            put(&mut auth.0.borrow_mut().read, "refs", Json::Array(Vec::new()));
        }
        let s = session(auth);
        assert!(s.borrow().store.ensure_healthy().is_ok(), "NATIVE_SELECTED_SCOPE_REACH: initial store must be healthy");
        assert_eq!(s.borrow().store.receipt_count(), 0, "NATIVE_SELECTED_SCOPE_REACH: initial receipt count");
        assert_eq!(field(s.borrow().store.facts(), "external_read").unwrap(), &Json::Bool(false));
        assert_eq!(field(s.borrow().store.facts(), "unknown_source").unwrap(), &Json::Bool(false));
        let a = run(&s);
        assert_eq!(s.borrow().dispatch_attempts, 1, "NATIVE_SELECTED_SCOPE_REACH: actual common-driver dispatch required");
        if permitted {
            assert_eq!(a.state.status, "completed", "NATIVE_SELECTED_SCOPE_REACH: valid sibling must complete");
            assert_eq!(s.borrow().handler_calls, 1, "NATIVE_SELECTED_SCOPE_REACH: valid sibling must read");
            assert_eq!(s.borrow().store.receipt_count(), 1, "NATIVE_SELECTED_SCOPE_REACH: valid sibling original receipt");
            assert!(s.borrow().store.ensure_healthy().is_ok());
        } else {
            assert_eq!(s.borrow().handler_calls, 0, "NATIVE_SELECTED_SCOPE_REACH: independent durable guard still prevents physical read");
            assert_eq!(s.borrow().store.receipt_count(), 0, "NATIVE_SELECTED_SCOPE_REACH: no receipt may commit");
            eprintln!("NATIVE_SELECTED_SCOPE_REACHED sibling=completed dispatches=1 reads=0 receipts=0");
            let admitted = match field(s.borrow().store.facts(), "external_read").unwrap() {
                Json::Bool(value) => usize::from(*value),
                _ => panic!("NATIVE_SELECTED_SCOPE_REACH: external_read must be boolean"),
            };
            assert_eq!(admitted, 0, "NATIVE_SELECTED_SCOPE_BOUNDARY: missing refs must deny before dispatch facts");
            assert_eq!(field(s.borrow().store.facts(), "unknown_source").unwrap(), &Json::Bool(false));
            assert!(s.borrow().store.ensure_healthy().is_ok(), "NATIVE_SELECTED_SCOPE_BOUNDARY: early denial must preserve healthy store");
            assert_eq!(a.state.status, "failed");
            assert_eq!(a.state.reason, "native_host_refused");
        }
    }
}
