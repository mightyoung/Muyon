#[test]
fn second_followup_encoder_refusal_preserves_existing_group_chain_and_hold() {
    let (f, s, o, mut l, scope, p, child) = prepared_group();
    map_actual(&s, &o, &mut l, &scope, &p, &child);
    let ctx = approve_actual_tool(&s, &o, &p);
    let next = o
        .prepare_tool_followup_trusted(&s, &ctx, &p.request_id, Some(&Proof))
        .unwrap();
    let ctx = approve_actual_tool(&s, &o, &next);
    let before = o
        .request_chain(&p.request_id)
        .unwrap()
        .iter()
        .map(|v| v.request_id.clone())
        .collect::<Vec<_>>();
    let result = o.prepare_tool_followup_trusted(&s, &ctx, &next.request_id, Some(&Proof));
    assert!(
        matches!(result, Err("tool_history_invalid")),
        "existing encoder refusal must not be bypassed"
    );
    assert_eq!(
        o.request_chain(&p.request_id)
            .unwrap()
            .iter()
            .map(|v| v.request_id.clone())
            .collect::<Vec<_>>(),
        before
    );
    let last = next;
    assert_eq!(
        o.request_origin(&last.request_id)
            .unwrap()
            .root_request_id(),
        Some(p.request_id.as_str())
    );
    let gate = serde_json::to_value(s.group_request_gate(&last.request_id, &o, &l)).unwrap();
    assert_eq!(gate["canonical"]["request_id"], p.request_id);
    assert_eq!(gate["group_hold"], true);
    assert_eq!(gate["execution_authority"], false);
    let db = sqlite::Db::open(f.0.join("agent.sqlite").to_str().unwrap(), false, false).unwrap();
    db.exec(
        "DELETE FROM request_origins WHERE request_id=?",
        &[&p.request_id],
    )
    .unwrap();
    assert!(o.request_origin(&last.request_id).is_err());
    assert!(s.group_request_gate(&last.request_id, &o, &l).group_hold());
}
