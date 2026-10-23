use muyon_core::{
    agent::{owner::*, tools::*},
    business::BusinessStore,
    contract::{Revision, Scope},
    development_drafts::ConversationDraft,
    services::{
        draft_store::DraftStore,
        drafts::DraftRef,
        types::{IntentId, ScopeRef},
    },
};
use serde_json::{json, Value};
use std::{
    fs,
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Fixture {
    path: PathBuf,
    business: BusinessStore,
    owner: AgentOwner,
    config: Configuration,
    context: ToolsContext,
}
struct Proof;
impl HostedCostVerifier for Proof {
    fn prove(&self, _: &[u8], _: &str) -> Result<HostedCostBound> {
        HostedCostBound::verified(16384, 128)
    }
}
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "muyon-development-model-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        BusinessStore::initialize(&path.join("business.sqlite"), "workspace-a").unwrap();
        let business =
            BusinessStore::open_existing(&path.join("business.sqlite"), "workspace-a", "epoch-a")
                .unwrap();
        AgentOwner::initialize(&path.join("agent.sqlite"), "workspace-a").unwrap();
        let owner = AgentOwner::open(&path.join("agent.sqlite"), "workspace-a", "epoch-a").unwrap();
        let config = configure(&owner);
        let context = ToolsContext::current(&business, "session-a", "generation-a", None).unwrap();
        Self {
            path,
            business,
            owner,
            config,
            context,
        }
    }
    fn prepare(&self, restricted: bool) -> AgentPlan {
        let plan = if restricted {
            self.owner.prepare_chat_restricted(
                "conversation-a",
                "开发项目：增加离线草稿，修复导出错误",
                Some(&Proof),
                &["development_draft_propose"],
            )
        } else {
            self.owner.prepare_chat(
                "conversation-a",
                "开发项目：增加离线草稿，修复导出错误",
                Some(&Proof),
            )
        }
        .unwrap();
        self.owner
            .bind_tool_scope_trusted(&plan.request_id, &self.context)
            .unwrap();
        self.owner
            .confirm_trusted(&plan.request_id, &self.config.id)
            .unwrap();
        self.owner
            .claim_dispatch(
                &plan.request_id,
                &self.config.id,
                &self.config.settings.credential_generation,
            )
            .unwrap();
        plan
    }
    fn pending(&self) -> AgentPlan {
        let plan = self.prepare(true);
        self.owner
            .settle_response(&plan.request_id, &body(&args().to_string()))
            .unwrap();
        plan
    }
    fn draft(&self, request: &str) -> ConversationDraft {
        let proposal = self
            .owner
            .development_proposal_review(request, &self.context)
            .unwrap();
        let mut draft = ConversationDraft::new(
            DraftRef {
                owner_plugin_id: "development".into(),
                draft_id: proposal.draft_id,
                scope: scope(),
                revision: Revision::new(0),
            },
            proposal.conversation_id,
        )
        .unwrap();
        draft
            .apply(&Revision::new(0), proposal.patch, false)
            .unwrap();
        draft
    }
    fn drafts(&self) -> DraftStore {
        DraftStore::initialize(&self.path.join("drafts.sqlite"), &scope()).unwrap();
        DraftStore::open_existing(&self.path.join("drafts.sqlite"), &scope()).unwrap()
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
fn configure(owner: &AgentOwner) -> Configuration {
    owner
        .configure_trusted(Settings {
            credential_generation: "key-generation".into(),
            cap_micro_cny: Revision::new(1_000_000),
            max_calls: Revision::new(20),
            chat: true,
            search: true,
            price_revision: PRICE_REVISION.into(),
        })
        .unwrap()
}
fn scope() -> ScopeRef {
    ScopeRef {
        scope: Scope {
            workspace_id: "workspace-a".into(),
            project_id: None,
        },
        account_id: None,
        scope_generation: Revision::new(1),
    }
}
fn args() -> Value {
    json!({"project_name":"离线工作台","items":[{"kind":"requirement","text":"增加离线草稿"},{"kind":"bug","text":"修复导出错误"}]})
}
fn body(arguments: &str) -> String {
    json!({"id":"model-development","model":MODEL,"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_a","type":"function","function":{"name":"product_development_draft_propose","arguments":arguments}}]}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string()
}
fn intent() -> IntentId {
    IntentId::parse("save-model-draft").unwrap()
}

#[test]
fn explicit_catalog_settles_proposal_fixed_acceptance_save_and_consumes_without_followup() {
    let f = Fixture::new();
    let plan = f.pending();
    assert_eq!(plan.outbound_preview["tools"].as_array().unwrap().len(), 1);
    let proposal = f
        .owner
        .development_proposal_review(&plan.request_id, &f.context)
        .unwrap();
    assert_eq!(
        proposal.patch.items[0].sources[0].original_message,
        "开发项目：增加离线草稿，修复导出错误"
    );
    assert_eq!(
        proposal.patch.items[0].sources[0].end,
        "开发项目：增加离线草稿，修复导出错误".len()
    );
    assert_eq!(
        f.owner
            .development_proposal_review(&plan.request_id, &f.context)
            .unwrap()
            .digest,
        proposal.digest
    );
    let draft = f.draft(&plan.request_id);
    let envelope = draft.envelope().unwrap();
    let mut modified = envelope.clone();
    modified.content["items"][0]["text"]["manually_edited"] = json!(true);
    assert!(f
        .owner
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &modified, &intent())
        .is_err());
    let fixed = f
        .owner
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &envelope, &intent())
        .unwrap();
    assert_eq!(
        fixed,
        f.owner
            .begin_development_acceptance_trusted(
                &plan.request_id,
                &f.context,
                &envelope,
                &intent()
            )
            .unwrap()
    );
    assert!(f
        .owner
        .begin_development_acceptance_trusted(
            &plan.request_id,
            &f.context,
            &envelope,
            &IntentId::parse("other").unwrap()
        )
        .is_err());
    let store = f.drafts();
    let ack = store.save(&fixed.envelope, &fixed.save_intent).unwrap();
    let mut wrong = ack.clone();
    wrong.draft_ref.revision = Revision::new(2);
    assert!(f
        .owner
        .complete_development_acceptance_trusted(&plan.request_id, &f.context, &wrong)
        .is_err());
    assert_eq!(
        f.owner.lookup(&plan.request_id).unwrap().status,
        "tool_pending"
    );
    f.owner
        .complete_development_acceptance_trusted(&plan.request_id, &f.context, &ack)
        .unwrap();
    f.owner
        .complete_development_acceptance_trusted(&plan.request_id, &f.context, &ack)
        .unwrap();
    let observed = f.owner.lookup(&plan.request_id).unwrap();
    assert_eq!(observed.status, "tool_consumed");
    assert_eq!(observed.answer.unwrap()["turn"], "tool_call");
    assert_eq!(f.owner.request_chain(&plan.request_id).unwrap().len(), 1);
    let next = f
        .owner
        .prepare_chat("conversation-a", "继续", Some(&Proof))
        .unwrap();
    assert_eq!(
        next.outbound_preview["messages"],
        json!([{"role":"user","content":"继续"}])
    );
    assert_eq!(next.outbound_preview["tools"].as_array().unwrap().len(), 6);
}

#[test]
fn default_catalog_rejects_development_even_though_parser_recognizes_it() {
    let f = Fixture::new();
    let plan = f.prepare(false);
    assert_eq!(plan.outbound_preview["tools"].as_array().unwrap().len(), 6);
    assert_eq!(
        f.owner
            .settle_response(&plan.request_id, &body(&args().to_string()))
            .unwrap_err(),
        "tool_not_allowed"
    );
    assert_eq!(f.owner.lookup(&plan.request_id).unwrap().status, "unknown");
}

#[test]
fn unknown_extra_duplicate_fields_and_oversized_arguments_remain_unknown() {
    for raw in [
        r#"{"project_name":null,"items":[{"kind":"operation","text":"x"}]}"#.to_owned(),
        r#"{"project_name":null,"items":[{"kind":"bug","text":"x","manual":true}]}"#.to_owned(),
        r#"{"project_name":null,"items":[{"kind":"bug","text":"x"}],"scope":{}}"#.to_owned(),
        r#"{"project_name":null,"project_name":"duplicate","items":[{"kind":"bug","text":"x"}]}"#
            .to_owned(),
        json!({"project_name":null,"items":[{"kind":"bug","text":"x".repeat(8192)}]}).to_string(),
    ] {
        let f = Fixture::new();
        let plan = f.prepare(true);
        assert!(f
            .owner
            .settle_response(&plan.request_id, &body(&raw))
            .is_err());
        assert_eq!(f.owner.lookup(&plan.request_id).unwrap().status, "unknown");
        assert!(f
            .owner
            .development_proposal_review(&plan.request_id, &f.context)
            .is_err());
    }
}

#[test]
fn rejection_consumes_and_new_chat_has_no_tool_data() {
    let f = Fixture::new();
    let plan = f.pending();
    f.owner
        .reject_development_proposal_trusted(&plan.request_id, &f.context)
        .unwrap();
    assert_eq!(
        f.owner.lookup(&plan.request_id).unwrap().status,
        "tool_consumed"
    );
    assert!(f
        .owner
        .development_acceptance_original(&plan.request_id)
        .is_err());
    assert!(f
        .owner
        .prepare_chat("conversation-a", "继续", Some(&Proof))
        .is_ok());
}

#[test]
fn cancellation_changed_session_scope_and_configuration_cannot_begin_acceptance() {
    for mode in ["cancel", "session", "generation", "config"] {
        let f = Fixture::new();
        let plan = f.pending();
        let envelope = f.draft(&plan.request_id).envelope().unwrap();
        let other = ToolsContext::current(
            &f.business,
            if mode == "session" {
                "session-b"
            } else {
                "session-a"
            },
            if mode == "generation" {
                "generation-b"
            } else {
                "generation-a"
            },
            None,
        )
        .unwrap();
        if mode == "cancel" {
            f.owner.cancel_trusted(&plan.request_id).unwrap();
        }
        if mode == "config" {
            configure(&f.owner);
        }
        assert!(f
            .owner
            .begin_development_acceptance_trusted(&plan.request_id, &other, &envelope, &intent())
            .is_err());
    }
    let f = Fixture::new();
    let plan = f.pending();
    let mut envelope = f.draft(&plan.request_id).envelope().unwrap();
    envelope.draft_ref.scope.scope.project_id = Some("other-project".into());
    assert!(f
        .owner
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &envelope, &intent())
        .is_err());
}

#[test]
fn fixed_acceptance_does_not_reapply_over_manual_edits_and_recovers_original_save() {
    let f = Fixture::new();
    let plan = f.pending();
    let draft = f.draft(&plan.request_id);
    let envelope = draft.envelope().unwrap();
    let fixed = f
        .owner
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &envelope, &intent())
        .unwrap();
    let store = f.drafts();
    assert_eq!(
        store
            .lookup_save(&fixed.envelope.draft_ref, &fixed.save_intent)
            .unwrap(),
        None
    );
    let ack = store.save(&fixed.envelope, &fixed.save_intent).unwrap();
    // A crash after DraftStore commit but before owner settlement: edited content
    // moves on independently; recovery looks up the fixed original SaveAck.
    let mut edited = draft;
    edited.acknowledge_save(&fixed.save_intent, &ack).unwrap();
    let mut patch = f
        .owner
        .development_proposal_review(&plan.request_id, &f.context)
        .unwrap()
        .patch;
    patch.items[0].text.text = "人工更正，不得覆盖".into();
    edited
        .apply(&edited.revision().clone(), patch, true)
        .unwrap();
    let changed = edited.envelope().unwrap();
    let manual_intent = IntentId::parse("save-manual-edit").unwrap();
    store.save(&changed, &manual_intent).unwrap();
    assert!(f
        .owner
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &changed, &intent())
        .is_err());
    configure(&f.owner);
    assert!(f
        .owner
        .complete_development_acceptance_trusted(&plan.request_id, &f.context, &ack)
        .is_err());
    let original = f
        .owner
        .development_acceptance_original(&plan.request_id)
        .unwrap();
    let recovered = store
        .lookup_save(&original.envelope.draft_ref, &original.save_intent)
        .unwrap()
        .unwrap();
    f.owner
        .complete_development_acceptance_original_trusted(&plan.request_id, &recovered)
        .unwrap();
    assert_eq!(
        store
            .load("development", &original.envelope.draft_ref.draft_id)
            .unwrap()
            .unwrap()
            .content["items"][0]["text"]["text"],
        "人工更正，不得覆盖"
    );
    assert_eq!(
        f.owner.lookup(&plan.request_id).unwrap().status,
        "tool_consumed"
    );
}

#[test]
fn owner_restart_new_epoch_only_recovers_frozen_original_save_and_cancel_blocks_reaccept() {
    let f = Fixture::new();
    let path = f.path.join("restart-agent.sqlite");
    AgentOwner::initialize(&path, "workspace-a").unwrap();
    let owner = AgentOwner::open(&path, "workspace-a", "epoch-a").unwrap();
    let config = configure(&owner);
    let plan = owner
        .prepare_chat_restricted(
            "conversation-a",
            "增加离线草稿",
            Some(&Proof),
            &["development_draft_propose"],
        )
        .unwrap();
    owner
        .bind_tool_scope_trusted(&plan.request_id, &f.context)
        .unwrap();
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    owner
        .settle_response(&plan.request_id, &body(&args().to_string()))
        .unwrap();
    let proposal = owner
        .development_proposal_review(&plan.request_id, &f.context)
        .unwrap();
    let mut draft = ConversationDraft::new(
        DraftRef {
            owner_plugin_id: "development".into(),
            draft_id: proposal.draft_id,
            scope: scope(),
            revision: Revision::new(0),
        },
        proposal.conversation_id,
    )
    .unwrap();
    draft
        .apply(&Revision::new(0), proposal.patch, false)
        .unwrap();
    let envelope = draft.envelope().unwrap();
    let fixed = owner
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &envelope, &intent())
        .unwrap();
    let store = f.drafts();
    let ack = store.save(&fixed.envelope, &fixed.save_intent).unwrap();
    owner.cancel_trusted(&plan.request_id).unwrap();
    assert!(owner
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &envelope, &intent())
        .is_err());
    drop(owner);
    let restored = AgentOwner::open(&path, "workspace-a", "epoch-b").unwrap();
    assert_eq!(
        restored
            .development_acceptance_original(&plan.request_id)
            .unwrap(),
        fixed
    );
    assert!(restored
        .begin_development_acceptance_trusted(&plan.request_id, &f.context, &envelope, &intent())
        .is_err());
    assert!(restored
        .complete_development_acceptance_trusted(&plan.request_id, &f.context, &ack)
        .is_err());
    restored
        .complete_development_acceptance_original_trusted(&plan.request_id, &ack)
        .unwrap();
    assert_eq!(
        restored.lookup(&plan.request_id).unwrap().status,
        "tool_consumed"
    );
    assert_eq!(restored.request_chain(&plan.request_id).unwrap().len(), 1);
}
