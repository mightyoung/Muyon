use muyon_core::agent::owner::*;
use muyon_core::contract::Revision;
use serde_json::{json, Value};

struct FixtureProof;
impl HostedCostVerifier for FixtureProof {
    fn prove(&self, _: &[u8], _: &str) -> Result<HostedCostBound> {
        HostedCostBound::verified(16384, 128)
    }
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
