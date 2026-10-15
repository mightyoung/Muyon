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
