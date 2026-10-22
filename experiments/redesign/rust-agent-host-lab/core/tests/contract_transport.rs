use muyon_plugin_contract_lab::{object, parse, string, Json};
use muyon_rust_agent_host_lab::{
    contract_transport::{ContractTransport, InProcessCatalog},
    field,
};
fn j(s: &str) -> Json {
    parse(s.as_bytes()).unwrap()
}
fn req(cmd: &str, mut fields: Vec<(&str, Json)>) -> Json {
    fields.push(("protocol_version", j("1")));
    fields.push(("command", string(cmd)));
    object(fields)
}
fn send(t: &mut InProcessCatalog, cmd: &str, fields: Vec<(&str, Json)>) -> Json {
    t.request(req(cmd, fields)).unwrap()
}
fn okay(v: &Json) -> bool {
    field(v, "ok") == Ok(&Json::Bool(true))
}
fn register(t: &mut InProcessCatalog) -> Json {
    send(
        t,
        "register",
        vec![
            (
                "bundle",
                j(include_str!(
                    "../../../plugin-contract-lab/fixtures/equipment_loan.json"
                )),
            ),
            ("host_bindings", j("[\"host-equipment-read\"]")),
        ],
    )
}
fn auth() -> Json {
    j(
        r#"{"allowed":true,"available":true,"scope_allowed":true,"bindings":["host-equipment-read"],"revision":"a1","binding_revision":"b1","source_revision":"s1","rule_revision":"r1","scope":"selected-e1","refs":[{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1","schema_version":1},{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1","schema_version":1}]}"#,
    )
}
fn prepare(t: &mut InProcessCatalog) -> Json {
    send(
        t,
        "prepare",
        vec![
            ("operation", string("equipment_loan/inspect_equipment@1")),
            ("args", j(r#"{"equipment_key":"e1","include_loans":true}"#)),
            ("authority", auth()),
            ("invocation_id", string("i1")),
            ("receipt_owner", string("ToolRegistry")),
            ("receipt_identity", string("host-identity")),
        ],
    )
}
fn healthy(t: &mut InProcessCatalog) {
    let result = t.request(req("inspect", vec![]));
    assert!(
        result.as_ref().is_ok_and(okay),
        "TRANSPORT_RED: persistent in-process Catalog must decode a real bounded inspect reply"
    );
}
#[test]
fn persistent_catalog_keeps_generation_and_one_shot_ticket() {
    let mut t = InProcessCatalog::new();
    healthy(&mut t);
    assert_eq!(
        field(&send(&mut t, "inspect", vec![]), "generation"),
        Ok(&j("0"))
    );
    assert!(okay(&register(&mut t)));
    assert_eq!(
        field(&send(&mut t, "inspect", vec![]), "generation"),
        Ok(&j("1"))
    );
    let p = prepare(&mut t);
    assert!(okay(&p));
    let ticket = field(&p, "ticket").unwrap().clone();
    let invoked = send(
        &mut t,
        "invoke",
        vec![("ticket", ticket.clone()), ("authority", auth())],
    );
    assert!(okay(&invoked));
    assert_eq!(
        field(field(&invoked, "dispatch").unwrap(), "binding_id"),
        Ok(&string("host-equipment-read"))
    );
    let receipt = j(
        r#"{"owner":"ToolRegistry","invocation_id":"i1","binding_id":"host-equipment-read","identity":"host-identity"}"#,
    );
    let projection = j(
        r#"{"equipment":{"module_id":"equipment_loan","type":"equipment","key":"e1","revision":"1","schema_version":1},"label":"synthetic drill","loans":[{"module_id":"equipment_loan","type":"loan","key":"l1","revision":"1","schema_version":1}]}"#,
    );
    let accepted = send(
        &mut t,
        "accept_result",
        vec![
            ("ticket", ticket.clone()),
            ("authority", auth()),
            ("receipt_ref", receipt.clone()),
            ("projection", projection.clone()),
        ],
    );
    assert!(okay(&accepted));
    assert_eq!(field(&accepted, "receipt_ref"), Ok(&receipt));
    assert_eq!(field(&accepted, "projection"), Ok(&projection));
    assert_eq!(
        field(
            &send(
                &mut t,
                "invoke",
                vec![("ticket", ticket), ("authority", auth())]
            ),
            "code"
        ),
        Ok(&string("unknown_ticket"))
    );
}
#[test]
fn tickets_cannot_cross_catalog_instances() {
    let mut a = InProcessCatalog::new();
    let mut b = InProcessCatalog::new();
    healthy(&mut a);
    healthy(&mut b);
    assert!(okay(&register(&mut a)));
    assert!(okay(&register(&mut b)));
    let ticket = field(&prepare(&mut a), "ticket").unwrap().clone();
    assert_eq!(
        field(
            &send(
                &mut b,
                "invoke",
                vec![("ticket", ticket.clone()), ("authority", auth())]
            ),
            "code"
        ),
        Ok(&string("unknown_ticket"))
    );
    assert!(okay(&send(
        &mut a,
        "invoke",
        vec![("ticket", ticket), ("authority", auth())]
    )));
}
#[test]
fn recoverable_schema_rejection_preserves_catalog() {
    let mut t = InProcessCatalog::new();
    healthy(&mut t);
    let mut bundle = j(include_str!(
        "../../../plugin-contract-lab/fixtures/equipment_loan.json"
    ));
    if let Json::Object(m) = &mut bundle {
        if let Json::Array(ops) = m.get_mut("operations").unwrap() {
            if let Json::Object(op) = &mut ops[0] {
                op.insert("effect".into(), string("write"));
            }
        }
    }
    let denied = send(
        &mut t,
        "register",
        vec![
            ("bundle", bundle),
            ("host_bindings", j("[\"host-equipment-read\"]")),
        ],
    );
    assert_eq!(field(&denied, "code"), Ok(&string("read_only")));
    assert_eq!(
        field(&send(&mut t, "inspect", vec![]), "generation"),
        Ok(&j("0"))
    );
    assert!(okay(&register(&mut t)));
}
#[test]
fn fatal_envelope_replies_latch_transport_closed() {
    for (line, code) in [
        (
            b"{\"protocol_version\":2,\"command\":\"inspect\"}\n".as_slice(),
            "protocol_version",
        ),
        (
            b"{\"protocol_version\":1}\n".as_slice(),
            "protocol_envelope",
        ),
        (
            b"{\"protocol_version\":1,\"command\":\"other\"}\n".as_slice(),
            "unsupported_command",
        ),
        (
            b"{\"protocol_version\":1,\"command\":\"inspect\",\"unexpected\":0}\n".as_slice(),
            "unexpected_or_missing_field",
        ),
    ] {
        let mut t = InProcessCatalog::new();
        healthy(&mut t);
        let denied = t.request_line(line).unwrap();
        assert_eq!(field(&denied, "code"), Ok(&string(code)));
        assert_eq!(
            t.request(req("inspect", vec![])).unwrap_err(),
            "plugin_closed"
        );
    }
}
#[test]
fn raw_frames_enforce_utf8_duplicates_depth_and_limits() {
    let mut deep = "[".repeat(33);
    deep.push('0');
    deep.push_str(&"]".repeat(33));
    deep.push('\n');
    for line in [
        b"\xff\n".to_vec(),
        b"{\"a\":1,\"a\":2}\n".to_vec(),
        deep.into_bytes(),
    ] {
        let mut t = InProcessCatalog::new();
        healthy(&mut t);
        assert_eq!(
            field(&t.request_line(&line).unwrap(), "code"),
            Ok(&string("invalid_json"))
        );
        assert_eq!(
            t.request(req("inspect", vec![])).unwrap_err(),
            "plugin_closed"
        );
    }
    for line in [b"{}".to_vec(), vec![b'x'; 65538]] {
        let mut t = InProcessCatalog::new();
        healthy(&mut t);
        assert_eq!(
            field(&t.request_line(&line).unwrap(), "code"),
            Ok(&string("frame_limit_or_eof"))
        );
        assert_eq!(
            t.request(req("inspect", vec![])).unwrap_err(),
            "plugin_closed"
        );
    }
    let mut t = InProcessCatalog::new();
    healthy(&mut t);
    assert_eq!(
        t.request(string("x".repeat(65536))).unwrap_err(),
        "plugin_frame_limit"
    );
    assert_eq!(
        t.request(req("inspect", vec![])).unwrap_err(),
        "plugin_closed"
    );
}
#[test]
fn explicit_transport_close_rejects_future_inspection() {
    let mut t = InProcessCatalog::new();
    healthy(&mut t);
    assert!(okay(&register(&mut t)));
    assert!(okay(&prepare(&mut t)));
    t.close();
    t.close();
    assert_eq!(
        t.request(req("inspect", vec![])).unwrap_err(),
        "plugin_closed"
    );
}
#[test]
fn wire_close_retains_child_command_inspection_semantics() {
    let mut t = InProcessCatalog::new();
    healthy(&mut t);
    assert!(okay(&send(&mut t, "close", vec![])));
    assert!(okay(&send(&mut t, "inspect", vec![])));
    assert_eq!(field(&register(&mut t), "code"), Ok(&string("closed")));
    t.close();
    assert_eq!(
        t.request(req("inspect", vec![])).unwrap_err(),
        "plugin_closed"
    );
}

#[test]
fn embedded_line_feed_is_fatal_but_crlf_sibling_is_valid() {
    let mut t = InProcessCatalog::new();
    healthy(&mut t);
    let valid = t
        .request_line(b"{\"protocol_version\":1,\"command\":\"inspect\"}\r\n")
        .unwrap();
    assert!(
        okay(&valid),
        "valid CRLF sibling must inspect the same live Catalog"
    );
    let reply = t
        .request_line(b"{\n\"protocol_version\":1,\"command\":\"inspect\"}\n")
        .unwrap();
    assert_eq!(
        field(&reply, "code"),
        Ok(&string("invalid_json")),
        "TRANSPORT_LINE_BOUNDARY: first LF ends the JSON frame, never parse a multiline object"
    );
    assert_eq!(
        t.request(req("inspect", vec![])).unwrap_err(),
        "plugin_closed"
    );
}
