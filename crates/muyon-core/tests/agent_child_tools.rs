use muyon_core::agent::owner::*;
use muyon_core::contract::Revision;
use serde_json::{json, Value};

struct FixtureProof;
impl HostedCostVerifier for FixtureProof {
    fn prove(&self, _: &[u8], _: &str) -> Result<HostedCostBound> {
        HostedCostBound::verified(16384, 128)
    }
}

fn fixture_owner(label: &str) -> (AgentOwner, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("muyon-review-{label}-{}", std::process::id()));
    std::fs::create_dir(&path).unwrap();
    let file = path.join("agent.sqlite");
    AgentOwner::initialize(&file, "workspace").unwrap();
    let owner = AgentOwner::open(&file, "workspace", "epoch").unwrap();
    owner
        .configure_trusted(Settings {
            credential_generation: "fixture-generation".into(),
            cap_micro_cny: Revision::new(1000000),
            max_calls: Revision::new(10),
            chat: true,
            search: false,
            price_revision: PRICE_REVISION.into(),
        })
        .unwrap();
    (owner, path)
}

#[test]
fn preprepared_plan_cannot_bypass_a_later_unknown_request() {
    let (owner, path) = fixture_owner("preprepared");
    let first = owner
        .prepare_chat("same", "first", Some(&FixtureProof))
        .unwrap();
    let second = owner
        .prepare_chat("same", "second", Some(&FixtureProof))
        .unwrap();
    owner
        .confirm_trusted(&first.request_id, &first.configuration_id)
        .unwrap();
    owner
        .claim_dispatch(
            &first.request_id,
            &first.configuration_id,
            "fixture-generation",
        )
        .unwrap();
    let held = owner.budget().unwrap().held_micro_cny;
    assert_eq!(
        owner
            .confirm_trusted(&second.request_id, &second.configuration_id)
            .unwrap_err(),
        "conversation_original_outcome_required"
    );
    assert_eq!(owner.lookup(&second.request_id).unwrap().status, "prepared");
    assert_eq!(owner.budget().unwrap().held_micro_cny, held);
    drop(owner);
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn confirmation_preview_contains_the_exact_prior_history_and_wire_fields() {
    let (owner, path) = fixture_owner("preview");
    let first = owner
        .prepare_chat("same", "prior user context", Some(&FixtureProof))
        .unwrap();
    owner
        .confirm_trusted(&first.request_id, &first.configuration_id)
        .unwrap();
    owner
        .claim_dispatch(
            &first.request_id,
            &first.configuration_id,
            "fixture-generation",
        )
        .unwrap();
    let response = json!({"id":"fixture","model":MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"prior answer"}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
    owner.settle_response(&first.request_id, &response).unwrap();
    let next = owner
        .prepare_chat("same", "new question", Some(&FixtureProof))
        .unwrap();
    let preview = serde_json::to_value(&next).unwrap();
    let body = preview
        .get("outbound_preview")
        .expect("exact outgoing body must be reviewed");
    assert_eq!(body["messages"][0]["content"], "prior user context");
    assert_eq!(body["messages"][1]["content"], "prior answer");
    assert_eq!(body["messages"][2]["content"], "new question");
    assert!(body["tools"].as_array().is_some());
    owner
        .confirm_trusted(&next.request_id, &next.configuration_id)
        .unwrap();
    let dispatch = owner
        .claim_dispatch(
            &next.request_id,
            &next.configuration_id,
            "fixture-generation",
        )
        .unwrap();
    assert_eq!(
        *body,
        serde_json::from_str::<Value>(&dispatch.payload).unwrap()
    );
    drop(owner);
    std::fs::remove_dir_all(path).unwrap();
}

#[test]
fn child_tool_subset_is_priced_and_enforced_on_the_actual_model_response() {
    let path = std::env::temp_dir().join(format!("muyon-child-tool-{}", std::process::id()));
    std::fs::create_dir(&path).unwrap();
    let file = path.join("agent.sqlite");
    AgentOwner::initialize(&file, "workspace").unwrap();
    let owner = AgentOwner::open(&file, "workspace", "epoch").unwrap();
    owner
        .configure_trusted(Settings {
            credential_generation: "fixture-generation".into(),
            cap_micro_cny: Revision::new(1000000),
            max_calls: Revision::new(10),
            chat: true,
            search: false,
            price_revision: PRICE_REVISION.into(),
        })
        .unwrap();
    assert!(owner
        .prepare_chat_restricted(
            "invalid",
            "task",
            Some(&FixtureProof),
            &["supplier_suggest", "invented"]
        )
        .is_err());
    let plan = owner
        .prepare_chat_restricted(
            "child",
            "list suppliers",
            Some(&FixtureProof),
            &["supplier_list"],
        )
        .unwrap();
    owner
        .confirm_trusted(&plan.request_id, &plan.configuration_id)
        .unwrap();
    let dispatch = owner
        .claim_dispatch(
            &plan.request_id,
            &plan.configuration_id,
            "fixture-generation",
        )
        .unwrap();
    let payload: Value = serde_json::from_str(&dispatch.payload).unwrap();
    assert_eq!(payload["tools"].as_array().unwrap().len(), 1);
    assert_eq!(
        payload["tools"][0]["function"]["name"],
        "product_supplier_list"
    );
    let reply = |name: &str| {
        json!({"id":"fixture","model":MODEL,"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-one","type":"function","function":{"name":name,"arguments":"{\"limit\":1,\"offset\":0}"}}]}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string()
    };
    assert_eq!(
        owner
            .settle_response(&plan.request_id, &reply("product_paper_list"))
            .unwrap_err(),
        "tool_not_allowed"
    );
    assert_eq!(owner.lookup(&plan.request_id).unwrap().status, "unknown");
    assert_eq!(
        owner.budget().unwrap().held_micro_cny,
        plan.reserved_micro_cny
    );
    assert_eq!(
        owner
            .settle_response(&plan.request_id, &reply("product_supplier_list"))
            .unwrap()
            .status,
        "tool_pending"
    );
    drop(owner);
    std::fs::remove_dir_all(path).unwrap();
}
