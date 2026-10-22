use muyon_core::{agent::owner::*, contract::Revision};
use serde_json::json;
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
            "muyon-agent-owner-{}-{}",
            std::process::id(),
            COUNT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn path(&self) -> PathBuf {
        self.0.join("agent.sqlite")
    }
    fn owner(&self) -> AgentOwner {
        AgentOwner::initialize(&self.path(), "workspace-a").unwrap();
        self.reopen("epoch-a")
    }
    fn reopen(&self, epoch: &str) -> AgentOwner {
        AgentOwner::open(&self.path(), "workspace-a", epoch).unwrap()
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn settings(cap: u64, calls: u64) -> Settings {
    Settings {
        credential_generation: "fresh-product-generation-a".into(),
        cap_micro_cny: Revision::new(cap),
        max_calls: Revision::new(calls),
        chat: true,
        search: true,
        price_revision: PRICE_REVISION.into(),
    }
}
// Explicit test-only cost authority; never installed in production or FFI.
struct FixtureProof;
struct FixturePrice;
impl SearchPriceVerifier for FixturePrice {
    fn prove(&self, endpoint: &str, _payload: &[u8], _revision: &str) -> Result<u64> {
        assert_eq!(endpoint, "https://api.deepseek.com/v1/tools/search");
        Ok(5000)
    }
}
impl HostedCostVerifier for FixtureProof {
    fn prove(&self, payload: &[u8], revision: &str) -> Result<HostedCostBound> {
        assert_eq!(revision, PRICE_REVISION);
        assert!(payload.starts_with(b"{"));
        HostedCostBound::verified(1000, 128)
    }
}
fn response(answer: &str) -> String {
    json!({"id":"test-only-provider-response","model":MODEL,"choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":answer}}],"usage":{"prompt_tokens":17,"completion_tokens":4,"total_tokens":21}}).to_string()
}

#[test]
fn fresh_product_settings_and_blocked_chat_plan_do_not_inherit_canary_authority() {
    let temp = Temp::new();
    let owner = temp.owner();
    assert!(owner.configuration().is_err());
    let config = owner.configure_trusted(settings(10000, 2)).unwrap();
    let plan = owner
        .prepare_chat("conversation-a", "普通用户输入", None)
        .unwrap();
    assert!(!plan.send_allowed);
    assert_eq!(
        plan.blocked_reason.as_deref(),
        Some("hosted_cost_proof_unavailable")
    );
    assert!(owner.confirm_trusted(&plan.request_id, &config.id).is_err());
    assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 0);
    let search = owner
        .prepare_search("conversation-b", "普通搜索", 3)
        .unwrap();
    assert!(!search.send_allowed);
    assert_eq!(
        search.blocked_reason.as_deref(),
        Some("search_price_proof_unavailable")
    );
    assert!(owner
        .confirm_trusted(&search.request_id, &config.id)
        .is_err());
    assert!(AgentOwner::initialize(&temp.path(), "workspace-a").is_err());
    assert!(AgentOwner::open(&temp.path(), "workspace-a", "other-owner").is_err());
}

#[test]
fn process_death_after_reservation_or_claim_keeps_original_hold_without_replay() {
    if let Ok(path) = std::env::var("MUYON_PRODUCT_OWNER_CHILD") {
        use std::io::Write;
        let path = PathBuf::from(path);
        AgentOwner::initialize(&path, "workspace-a").unwrap();
        let owner = AgentOwner::open(&path, "workspace-a", "epoch-child").unwrap();
        let config = owner.configure_trusted(settings(10000, 2)).unwrap();
        let plan = owner
            .prepare_search_with_price(
                "conversation-a",
                "synthetic crash sample",
                1,
                Some(&FixturePrice),
            )
            .unwrap();
        owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
        if std::env::var("MUYON_PRODUCT_OWNER_PHASE").unwrap() == "claimed" {
            owner
                .claim_dispatch(
                    &plan.request_id,
                    &config.id,
                    &config.settings.credential_generation,
                )
                .unwrap();
        }
        println!("OWNER_READY={}", plan.request_id);
        std::io::stdout().flush().unwrap();
        loop {
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    }
    use std::{
        io::{BufRead, BufReader},
        process::{Command, Stdio},
        sync::mpsc,
        time::Duration,
    };
    struct Child(std::process::Child);
    impl Drop for Child {
        fn drop(&mut self) {
            let _ = self.0.kill();
            let _ = self.0.wait();
        }
    }
    for phase in ["reserved", "claimed"] {
        let temp = Temp::new();
        let mut child = Child(
            Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "process_death_after_reservation_or_claim_keeps_original_hold_without_replay",
                    "--nocapture",
                ])
                .env("MUYON_PRODUCT_OWNER_CHILD", temp.path())
                .env("MUYON_PRODUCT_OWNER_PHASE", phase)
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
                .unwrap(),
        );
        let stdout = child.0.stdout.take().unwrap();
        let (send, receive) = mpsc::channel();
        let reader = std::thread::spawn(move || {
            for line in BufReader::new(stdout)
                .lines()
                .map_while(std::result::Result::ok)
            {
                if let Some((_, request)) = line.split_once("OWNER_READY=") {
                    let _ = send.send(request.trim().to_owned());
                    break;
                }
            }
        });
        let request = receive
            .recv_timeout(Duration::from_secs(10))
            .expect("child must persist reservation before kill");
        child.0.kill().unwrap();
        assert!(!child.0.wait().unwrap().success());
        reader.join().unwrap();
        let owner = temp.reopen("epoch-recovered");
        assert_eq!(
            owner.lookup(&request).unwrap().status,
            "unknown",
            "phase={phase}"
        );
        let config = owner.configure_trusted(settings(10000, 2)).unwrap();
        assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 5000);
        assert!(owner
            .claim_dispatch(&request, &config.id, &config.settings.credential_generation)
            .is_err());
        assert!(owner.confirm_trusted(&request, &config.id).is_err());
    }
}
#[test]
fn reserve_claim_exactly_once_and_unknown_never_resends_after_reopen() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(20000, 3)).unwrap();
    let plan = owner
        .prepare_search_with_price("conversation-a", "query", 3, Some(&FixturePrice))
        .unwrap();
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    let dispatch = owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    assert_eq!(dispatch.purpose, "search");
    assert!(owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation
        )
        .is_err());
    assert_eq!(owner.lookup(&plan.request_id).unwrap().status, "unknown");
    drop(owner);
    let reopened = temp.reopen("epoch-b");
    assert!(reopened.configuration().is_err());
    let config = reopened.configure_trusted(settings(20000, 3)).unwrap();
    assert_eq!(reopened.budget().unwrap().held_micro_cny.value(), 5000);
    assert!(reopened
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation
        )
        .is_err());
    assert_eq!(
        reopened.lookup(&plan.request_id).unwrap().recovery_action,
        "query_original"
    );
}
#[test]
fn cumulative_budget_survives_reconfiguration_and_unknown_is_not_refunded() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(5000, 1)).unwrap();
    let a = owner
        .prepare_search_with_price("conversation-a", "one", 1, Some(&FixturePrice))
        .unwrap();
    owner.confirm_trusted(&a.request_id, &config.id).unwrap();
    owner
        .claim_dispatch(
            &a.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    owner.cancel_trusted(&a.request_id).unwrap();
    let config = owner.configure_trusted(settings(5000, 1)).unwrap();
    assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 5000);
    let b = owner
        .prepare_search_with_price("conversation-b", "two", 1, Some(&FixturePrice))
        .unwrap();
    assert!(owner.confirm_trusted(&b.request_id, &config.id).is_err());
    assert!(owner.configure_trusted(settings(4999, 2)).is_err());
    assert_eq!(owner.lookup(&a.request_id).unwrap().status, "unknown");
}
#[test]
fn cancel_before_attempt_releases_only_held_identity_and_is_not_replayable() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(5000, 1)).unwrap();
    let plan = owner
        .prepare_search_with_price("conversation-a", "one", 1, Some(&FixturePrice))
        .unwrap();
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    let cancelled = owner.cancel_trusted(&plan.request_id).unwrap();
    assert_eq!(cancelled.status, "cancelled");
    assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 0);
    assert!(owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation
        )
        .is_err());
    assert!(owner.confirm_trusted(&plan.request_id, &config.id).is_err());
}
#[test]
fn complete_chat_usage_settles_once_and_restores_bounded_conversation_history() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(10000, 3)).unwrap();
    let plan = owner
        .prepare_chat("conversation-a", "记住样本42", Some(&FixtureProof))
        .unwrap();
    assert!(plan.send_allowed);
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    assert!(owner
        .prepare_chat("conversation-a", "还记得吗", Some(&FixtureProof))
        .is_err());
    assert!(owner
        .settle_response(&plan.request_id, "HTTP/1.1 200 OK")
        .is_err());
    assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 3024);
    let settled = owner
        .settle_response(&plan.request_id, &response("已记住样本42"))
        .unwrap();
    assert_eq!(settled.status, "completed");
    assert_eq!(settled.charged_micro_cny.value(), 66);
    assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 0);
    assert!(owner
        .settle_response(&plan.request_id, &response("重复"))
        .is_err());
    let next = owner
        .prepare_chat("conversation-a", "还记得吗", Some(&FixtureProof))
        .unwrap();
    owner.confirm_trusted(&next.request_id, &config.id).unwrap();
    let next = owner
        .claim_dispatch(
            &next.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    let payload: serde_json::Value = serde_json::from_str(&next.payload).unwrap();
    assert_eq!(payload["messages"].as_array().unwrap().len(), 3);
    assert_eq!(payload["messages"][1]["content"], "已记住样本42");
}
#[test]
fn config_or_credential_changes_deny_dispatch_and_suppress_revoked_disclosure() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(20000, 3)).unwrap();
    let plan = owner
        .prepare_chat("conversation-a", "问题", Some(&FixtureProof))
        .unwrap();
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    assert!(owner
        .claim_dispatch(&plan.request_id, &config.id, "wrong-generation")
        .is_err());
    owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    assert!(owner.dispatch_allowed(
        &plan.request_id,
        &config.id,
        &config.settings.credential_generation
    ));
    let mut changed = settings(20000, 3);
    changed.credential_generation = "fresh-product-generation-b".into();
    owner.configure_trusted(changed).unwrap();
    assert!(!owner.dispatch_allowed(
        &plan.request_id,
        &config.id,
        &config.settings.credential_generation
    ));
    let settled = owner
        .settle_response(&plan.request_id, &response("不能披露旧授权结果"))
        .unwrap();
    assert_eq!(settled.status, "cancelled");
    assert!(settled.answer.unwrap().is_null());
    assert_eq!(settled.charged_micro_cny.value(), 66);
}
#[test]
fn malformed_or_over_bound_usage_keeps_unknown_hold_without_answer() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(10000, 2)).unwrap();
    let plan = owner
        .prepare_chat("conversation-a", "问题", Some(&FixtureProof))
        .unwrap();
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    for body in [
        response("Bearer forbidden"),
        response("正常回答").replace("\"prompt_tokens\":17", "\"prompt_tokens\":1001"),
        response("正常回答").replace("\"finish_reason\":\"stop\"", "\"finish_reason\":\"length\""),
    ] {
        assert!(owner.settle_response(&plan.request_id, &body).is_err());
        assert_eq!(owner.lookup(&plan.request_id).unwrap().status, "unknown");
        assert!(owner.lookup(&plan.request_id).unwrap().answer.is_none());
        assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 3024);
    }
}

#[test]
fn validated_search_sources_and_empty_result_follow_existing_settlement_contract() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(10000, 3)).unwrap();
    let empty = owner
        .prepare_search_with_price(
            "conversation-a",
            "zero-result sample",
            3,
            Some(&FixturePrice),
        )
        .unwrap();
    owner
        .confirm_trusted(&empty.request_id, &config.id)
        .unwrap();
    owner
        .claim_dispatch(
            &empty.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    let result = owner
        .settle_response(&empty.request_id, r#"{"results":[]}"#)
        .unwrap();
    assert_eq!(result.status, "completed");
    assert_eq!(
        result.charged_micro_cny.value(),
        5000,
        "empty results do not waive a verified per-request charge"
    );
    assert_eq!(result.answer, Some(json!([])));
    assert!(owner
        .claim_dispatch(
            &empty.request_id,
            &config.id,
            &config.settings.credential_generation
        )
        .is_err());
    let nonempty = owner
        .prepare_search_with_price("conversation-b", "source sample", 3, Some(&FixturePrice))
        .unwrap();
    owner
        .confirm_trusted(&nonempty.request_id, &config.id)
        .unwrap();
    owner
        .claim_dispatch(
            &nonempty.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    let body=json!({"results":[{"title":"synthetic source","url":"https://example.com/paper","snippet":"external text","summary":"summary","content":"","site_name":null,"site_icon":null,"date":null,"rerank_score":0.7,"authority":0}]}).to_string();
    let result = owner.settle_response(&nonempty.request_id, &body).unwrap();
    assert_eq!(result.status, "completed");
    assert_eq!(result.charged_micro_cny.value(), 5000);
    assert!(result
        .answer
        .unwrap()
        .to_string()
        .contains("https://example.com/paper"));
    assert_eq!(owner.budget().unwrap().charged_micro_cny.value(), 10000);
}

#[test]
fn cancelled_claim_with_empty_response_never_refunds_attempt_count_after_restart() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(10000, 1)).unwrap();
    let plan = owner
        .prepare_search_with_price("conversation-a", "synthetic empty", 1, Some(&FixturePrice))
        .unwrap();
    owner.confirm_trusted(&plan.request_id, &config.id).unwrap();
    owner
        .claim_dispatch(
            &plan.request_id,
            &config.id,
            &config.settings.credential_generation,
        )
        .unwrap();
    owner.cancel_trusted(&plan.request_id).unwrap();
    let terminal = owner
        .settle_response(&plan.request_id, r#"{"results":[]}"#)
        .unwrap();
    assert_eq!(terminal.status, "cancelled");
    assert_eq!(terminal.charged_micro_cny.value(), 5000);
    assert_eq!(
        owner.budget().unwrap().used_calls.value(),
        1,
        "attempted call cannot disappear after empty/cancel settlement"
    );
    drop(owner);
    let owner = temp.reopen("epoch-new");
    let config = owner.configure_trusted(settings(10000, 1)).unwrap();
    assert_eq!(owner.budget().unwrap().used_calls.value(), 1);
    let next = owner
        .prepare_search_with_price("conversation-b", "second", 1, Some(&FixturePrice))
        .unwrap();
    assert!(owner.confirm_trusted(&next.request_id, &config.id).is_err());
}

#[test]
fn fixed_transport_diagnostic_survives_reopen_without_settlement_or_raw_text() {
    let temp = Temp::new();
    let owner = temp.owner();
    let config = owner.configure_trusted(settings(10000, 2)).unwrap();
    let plan = owner
        .prepare_search_with_price(
            "conversation-a",
            "synthetic diagnostic sample",
            1,
            Some(&FixturePrice),
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
    owner
        .record_diagnostic(&plan.request_id, "HTTP_STATUS", Some(403))
        .unwrap();
    assert!(owner
        .record_diagnostic(&plan.request_id, "Bearer private-untrusted-body", Some(403))
        .is_err());
    assert!(owner
        .record_diagnostic(&plan.request_id, "WRITE", Some(999))
        .is_err());
    drop(owner);
    let owner = temp.reopen("epoch-new");
    let result = owner.lookup(&plan.request_id).unwrap();
    assert_eq!(result.status, "unknown");
    assert!(result.attempted);
    assert_eq!(result.failure_stage.as_deref(), Some("HTTP_STATUS"));
    assert_eq!(result.http_status, Some(403));
    assert_eq!(result.reserved_micro_cny.value(), 5000);
    assert_eq!(result.charged_micro_cny.value(), 0);
    assert!(result.answer.is_none());
    assert_eq!(owner.budget().unwrap().held_micro_cny.value(), 5000);
    assert_eq!(owner.budget().unwrap().used_calls.value(), 1);
}
