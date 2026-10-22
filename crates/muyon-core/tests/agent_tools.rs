use muyon_core::{
    agent::{owner::*, tools::*},
    business::BusinessStore,
    contract::*,
};
use serde_json::{json, Value};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static COUNT: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "muyon-tools-{}-{}",
            std::process::id(),
            COUNT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn store(&self) -> BusinessStore {
        let p = self.0.join("business.sqlite");
        BusinessStore::initialize(&p, "workspace-a").unwrap();
        BusinessStore::open_existing(&p, "workspace-a", "epoch-a").unwrap()
    }
    fn owner(&self) -> AgentOwner {
        let p = self.0.join("agent.sqlite");
        AgentOwner::initialize(&p, "workspace-a").unwrap();
        AgentOwner::open(&p, "workspace-a", "epoch-a").unwrap()
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
struct FixtureProof;
impl HostedCostVerifier for FixtureProof {
    fn prove(&self, bytes: &[u8], _: &str) -> muyon_core::agent::owner::Result<HostedCostBound> {
        assert!(bytes.len() <= 8192);
        HostedCostBound::verified(16384, 128)
    }
}
fn configured(owner: &AgentOwner) -> Configuration {
    owner
        .configure_trusted(Settings {
            credential_generation: "fresh-key-generation".into(),
            cap_micro_cny: Revision::new(1_000_000),
            max_calls: Revision::new(10),
            chat: true,
            search: true,
            price_revision: PRICE_REVISION.into(),
        })
        .unwrap()
}
fn payload(name: &str) -> SupplierPayload {
    serde_json::from_value(json!({"name":name,"aliases":[],"address":"地址","categories":[],"notes":"备注","merged_into":null,"rating":null,"rating_note":null})).unwrap()
}
fn command(intent: &str, rev: u64, op: Operation) -> CommandEnvelope {
    let mut c = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: intent.into(),
        scope: Scope {
            workspace_id: "workspace-a".into(),
            project_id: None,
        },
        expected_revision: Revision::new(rev),
        authority: AuthorityBinding {
            grant_id: format!("grant-{intent}"),
            generation: Revision::new(1),
            owner_epoch: "epoch-a".into(),
        },
        plan_id: format!("plan-{intent}"),
        plan_digest: "0".repeat(64),
        command: op,
    };
    c.plan_digest = c.expected_plan_digest().unwrap();
    c
}
fn execute(store: &BusinessStore, c: &CommandEnvelope) {
    store.issue_grant_trusted(c, None).unwrap();
    assert_eq!(store.execute(c).unwrap().status, ExecutionStatus::Committed);
}
fn seed(store: &BusinessStore) {
    execute(
        store,
        &command(
            "seed",
            0,
            Operation::SupplierCreate {
                supplier_id: "supplier-a".into(),
                payload: payload("真实本地供应商"),
            },
        ),
    );
}
fn tool_body(name: &str, args: Value) -> String {
    json!({"id":"fixture-model-call","model":MODEL,"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_a","type":"function","function":{"name":name,"arguments":args.to_string()}}]}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string()
}
fn call(
    store: &BusinessStore,
    owner: &AgentOwner,
    config: &Configuration,
    name: &str,
    args: Value,
) -> AgentPlan {
    let plan = owner
        .prepare_chat("conversation-a", "读取或建议本地业务", Some(&FixtureProof))
        .unwrap();
    owner
        .bind_tool_scope_trusted(
            &plan.request_id,
            &ToolsContext::current(store, "session-a", "generation-a", None).unwrap(),
        )
        .unwrap();
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    let result = owner
        .settle_response(&plan.request_id, &tool_body(name, args))
        .unwrap();
    assert_eq!(result.status, "tool_pending");
    assert_eq!(result.charged_micro_cny.value(), 66);
    plan
}

#[test]
fn read_call_requires_exact_visible_disclosure_then_new_followup_identity_and_budget() {
    let temp = Temp::new();
    let store = temp.store();
    seed(&store);
    let owner = temp.owner();
    let config = configured(&owner);
    let plan = call(
        &store,
        &owner,
        &config,
        "product_supplier_get",
        json!({"id":"supplier-a"}),
    );
    let context = ToolsContext::current(&store, "session-a", "generation-a", None).unwrap();
    assert!(owner
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, Some(&FixtureProof))
        .is_err());
    let review = owner
        .review_tool_read(&store, &context, &plan.request_id)
        .unwrap();
    assert_eq!(
        review.values["records"][0]["payload"]["name"],
        "真实本地供应商"
    );
    assert_eq!(review.bytes, review.values.to_string());
    assert!(owner
        .approve_tool_read_trusted(&store, &context, &plan.request_id, &"0".repeat(64))
        .is_err());
    owner
        .approve_tool_read_trusted(&store, &context, &plan.request_id, &review.digest)
        .unwrap();
    let next = owner
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, Some(&FixtureProof))
        .unwrap();
    assert_ne!(next.request_id, plan.request_id);
    assert_eq!(owner.budget().unwrap().used_calls.value(), 1);
    assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 0);
    owner.confirm_trusted(&next.request_id, &config.id).unwrap();
    assert_eq!(owner.budget().unwrap().used_calls.value(), 2);
    let sent = owner
        .claim_dispatch(
            &next.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    let body: Value = serde_json::from_str(&sent.payload).unwrap();
    assert_eq!(
        body["messages"][1]["tool_calls"][0]["function"]["name"],
        "product_supplier_get"
    );
    assert_eq!(body["messages"][2]["role"], "tool");
    assert_eq!(body["messages"][2]["content"], review.bytes);
    assert!(!sent.payload.contains("outbound_authorized"));
    let answer=json!({"id":"fixture-followup-answer","model":MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"已读取经用户批准的本地供应商字段"}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string();
    assert_eq!(
        owner
            .settle_response(&next.request_id, &answer)
            .unwrap()
            .status,
        "completed"
    );
    assert!(
        owner
            .prepare_chat("conversation-a", "下一条消息", Some(&FixtureProof))
            .is_err(),
        "historical tool bytes must not be reused without new review"
    );
    let fresh = owner
        .prepare_chat("fresh-conversation", "开始新的会话", Some(&FixtureProof))
        .unwrap();
    owner
        .confirm_trusted(&fresh.request_id, &config.id)
        .unwrap();
    let fresh = owner
        .claim_dispatch(
            &fresh.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    assert!(!fresh.payload.contains("真实本地供应商"));
    assert!(owner
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, Some(&FixtureProof))
        .is_err());
}
#[test]
fn disclosure_is_not_inferred_from_budget_or_copied_to_new_scope_or_generation() {
    let temp = Temp::new();
    let store = temp.store();
    seed(&store);
    let owner = temp.owner();
    let config = configured(&owner);
    let plan = call(
        &store,
        &owner,
        &config,
        "product_supplier_get",
        json!({"id":"supplier-a"}),
    );
    let a = ToolsContext::current(&store, "session-a", "generation-a", None).unwrap();
    let b = ToolsContext::current(&store, "session-a", "generation-b", None).unwrap();
    let review = owner
        .review_tool_read(&store, &a, &plan.request_id)
        .unwrap();
    assert!(owner
        .approve_tool_read_trusted(&store, &b, &plan.request_id, &review.digest)
        .is_err());
    assert!(owner
        .prepare_tool_followup_trusted(&store, &a, &plan.request_id, Some(&FixtureProof))
        .is_err());
    execute(
        &store,
        &command(
            "change",
            1,
            Operation::SupplierUpdate {
                supplier_id: "supplier-a".into(),
                payload: payload("已变化"),
            },
        ),
    );
    assert!(owner
        .approve_tool_read_trusted(&store, &a, &plan.request_id, &review.digest)
        .is_err());
}
#[test]
fn production_unbound_proof_never_auto_sends_approved_tool_followup() {
    let temp = Temp::new();
    let store = temp.store();
    seed(&store);
    let owner = temp.owner();
    let config = configured(&owner);
    let plan = call(
        &store,
        &owner,
        &config,
        "product_supplier_list",
        json!({"limit":1,"offset":0}),
    );
    let context = ToolsContext::current(&store, "session-a", "generation-a", None).unwrap();
    let review = owner
        .review_tool_read(&store, &context, &plan.request_id)
        .unwrap();
    owner
        .approve_tool_read_trusted(&store, &context, &plan.request_id, &review.digest)
        .unwrap();
    let next = owner
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, None)
        .unwrap();
    assert!(!next.send_allowed);
    assert_eq!(next.reserved_micro_cny.value(), 0);
    assert!(owner.confirm_trusted(&next.request_id, &config.id).is_err());
    assert_eq!(owner.budget().unwrap().used_calls.value(), 1);
}
#[test]
fn suggestion_only_prepares_then_requires_original_committed_receipt_and_disclosure() {
    let temp = Temp::new();
    let store = temp.store();
    seed(&store);
    let owner = temp.owner();
    let config = configured(&owner);
    let operation = Operation::SupplierUpdate {
        supplier_id: "supplier-a".into(),
        payload: payload("模型建议的新名称"),
    };
    let plan = call(
        &store,
        &owner,
        &config,
        "product_supplier_suggest",
        json!({"operation":operation,"expected_revision":"1"}),
    );
    let context = ToolsContext::current(&store, "session-a", "generation-a", None).unwrap();
    let mut prepared = None;
    let view = owner
        .prepare_tool_suggestion(&context, &plan.request_id, |op, revision, project| {
            assert!(project.is_none());
            let c = command("model-suggestion", revision.value(), op);
            let result = HostPreparedSuggestion {
                view: PreparedSuggestion {
                    plan_id: c.plan_id.clone(),
                    summary: "更新供应商名称为模型建议的新名称；预期修订1".into(),
                },
                intent_id: c.intent_id.clone(),
                binding_digest: c.binding_digest().unwrap(),
            };
            prepared = Some(c);
            Ok(result)
        })
        .unwrap();
    assert_eq!(store.supplier("supplier-a").unwrap().revision.value(), 1);
    assert!(owner
        .review_tool_suggestion_result(&store, &context, &plan.request_id, &view.plan_id)
        .is_err());
    assert!(owner
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, Some(&FixtureProof))
        .is_err());
    // Only this independent visible P04 confirmation grants/commits the write.
    execute(&store, &prepared.unwrap());
    let review = owner
        .review_tool_suggestion_result(&store, &context, &plan.request_id, &view.plan_id)
        .unwrap();
    assert_eq!(review.values["status"], "committed");
    assert!(!review.bytes.contains("authority"));
    assert!(!review.bytes.contains("grant"));
    assert!(!review.bytes.contains("binding_digest"));
    assert!(owner
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, Some(&FixtureProof))
        .is_err());
    owner
        .approve_tool_suggestion_result_trusted(
            &store,
            &context,
            &plan.request_id,
            &view.plan_id,
            &review.digest,
        )
        .unwrap();
    let next = owner
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, Some(&FixtureProof))
        .unwrap();
    assert!(next.send_allowed);
    assert_eq!(store.supplier("supplier-a").unwrap().revision.value(), 2);
}
#[test]
fn malformed_function_calls_remain_unknown_and_have_no_business_effect() {
    for (name, args) in [
        ("confirm_user_plan", json!({"plan_id":"forged"})),
        (
            "product_supplier_get",
            json!({"id":"supplier-a","workspace_id":"other"}),
        ),
        ("product_supplier_list", json!({"limit":51,"offset":0})),
        (
            "product_supplier_suggest",
            json!({"operation":{"operation":"blob_release","blob":{"digest":"a".repeat(64),"byte_length":"1"}},"expected_revision":"0"}),
        ),
    ] {
        let temp = Temp::new();
        let store = temp.store();
        seed(&store);
        let owner = temp.owner();
        let config = configured(&owner);
        let p = owner
            .prepare_chat("conversation-a", "request", Some(&FixtureProof))
            .unwrap();
        owner.confirm_trusted(&p.request_id, &config.id).unwrap();
        owner
            .claim_dispatch(
                &p.request_id,
                &config.id,
                &config.settings.credential_generation,
            )
            .unwrap();
        assert!(owner
            .settle_response(&p.request_id, &tool_body(name, args))
            .is_err());
        assert_eq!(owner.lookup(&p.request_id).unwrap().status, "unknown");
        assert_eq!(store.supplier("supplier-a").unwrap().revision.value(), 1);
    }
}
#[test]
fn cancellation_restart_and_unknown_never_resume_or_approve_tool_disclosure() {
    let temp = Temp::new();
    let store = temp.store();
    seed(&store);
    let owner = temp.owner();
    let config = configured(&owner);
    let plan = call(
        &store,
        &owner,
        &config,
        "product_supplier_get",
        json!({"id":"supplier-a"}),
    );
    let context = ToolsContext::current(&store, "session-a", "generation-a", None).unwrap();
    let review = owner
        .review_tool_read(&store, &context, &plan.request_id)
        .unwrap();
    owner.cancel_trusted(&plan.request_id).unwrap();
    assert_eq!(owner.lookup(&plan.request_id).unwrap().status, "cancelled");
    assert!(owner
        .prepare_chat("conversation-a", "取消后的新普通轮次", Some(&FixtureProof))
        .is_ok());
    assert!(owner
        .approve_tool_read_trusted(&store, &context, &plan.request_id, &review.digest)
        .is_err());
    drop(owner);
    let reopened =
        AgentOwner::open(&temp.0.join("agent.sqlite"), "workspace-a", "epoch-b").unwrap();
    assert!(reopened
        .prepare_tool_followup_trusted(&store, &context, &plan.request_id, Some(&FixtureProof))
        .is_err());
    assert_eq!(reopened.budget().unwrap().used_calls.value(), 1);
}

#[test]
fn cancelled_or_changed_suggestion_is_revalidated_before_any_business_commit() {
    for revoke in ["cancel", "configuration", "scope_generation"] {
        let temp = Temp::new();
        let store = temp.store();
        seed(&store);
        let owner = temp.owner();
        let config = configured(&owner);
        let plan = call(
            &store,
            &owner,
            &config,
            "product_supplier_suggest",
            json!({"operation":Operation::SupplierUpdate{supplier_id:"supplier-a".into(),payload:payload("不得提交的建议")},"expected_revision":"1"}),
        );
        let context = ToolsContext::current(&store, "session-a", "generation-a", None).unwrap();
        let view = owner
            .prepare_tool_suggestion(&context, &plan.request_id, |op, revision, _| {
                let c = command("revoked-plan", revision.value(), op);
                Ok(HostPreparedSuggestion {
                    view: PreparedSuggestion {
                        plan_id: c.plan_id.clone(),
                        summary: "将改名，预期修订1".into(),
                    },
                    intent_id: c.intent_id.clone(),
                    binding_digest: c.binding_digest().unwrap(),
                })
            })
            .unwrap();
        assert!(owner
            .validate_tool_suggestion_trusted(&context, &plan.request_id, &view.plan_id)
            .is_ok());
        match revoke {
            "cancel" => {
                owner.cancel_trusted(&plan.request_id).unwrap();
                assert!(owner
                    .validate_tool_suggestion_trusted(&context, &plan.request_id, &view.plan_id)
                    .is_err());
            }
            "configuration" => {
                configured(&owner);
                assert!(owner
                    .validate_tool_suggestion_trusted(&context, &plan.request_id, &view.plan_id)
                    .is_err());
            }
            _ => {
                let changed =
                    ToolsContext::current(&store, "session-a", "generation-b", None).unwrap();
                assert!(owner
                    .validate_tool_suggestion_trusted(&changed, &plan.request_id, &view.plan_id)
                    .is_err());
            }
        }
        assert_eq!(store.supplier("supplier-a").unwrap().revision.value(), 1);
    }
}
