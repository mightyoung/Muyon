use muyon_core::{agent::*, blobs::BlobKind, business::BusinessStore, contract::*};
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
            "muyon-agent-{}-{}",
            std::process::id(),
            COUNT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&p).unwrap();
        Self(p)
    }
    fn path(&self) -> PathBuf {
        self.0.join("business.sqlite")
    }
    fn store(&self) -> BusinessStore {
        BusinessStore::initialize(&self.path(), "workspace-a").unwrap();
        BusinessStore::open_existing(&self.path(), "workspace-a", "epoch-a").unwrap()
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}
fn command(id: &str, project: Option<&str>, rev: u64, operation: Operation) -> CommandEnvelope {
    let mut command = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: id.into(),
        scope: Scope {
            workspace_id: "workspace-a".into(),
            project_id: project.map(str::to_owned),
        },
        expected_revision: Revision::new(rev),
        authority: AuthorityBinding {
            grant_id: format!("grant-{id}"),
            generation: Revision::new(1),
            owner_epoch: "epoch-a".into(),
        },
        plan_id: format!("plan-{id}"),
        plan_digest: "0".repeat(64),
        command: operation,
    };
    command.plan_digest = command.expected_plan_digest().unwrap();
    command
}
fn execute(store: &BusinessStore, command: &CommandEnvelope) {
    store.issue_grant_trusted(command, None).unwrap();
    assert_eq!(
        store.execute(command).unwrap().status,
        ExecutionStatus::Committed
    );
}
fn supplier(store: &BusinessStore) {
    execute(store,&command("supplier-create",None,0,Operation::SupplierCreate{supplier_id:"supplier-a".into(),payload:serde_json::from_value(json!({"name":"当前供应商","aliases":[],"address":"地址","categories":[],"notes":"私有备注","merged_into":null,"rating":null,"rating_note":null})).unwrap()}));
}
fn local(store: &BusinessStore, project: Option<&str>, request: Value) -> Value {
    read_business(
        store,
        &ReadScope::current(store, project).unwrap(),
        &request.to_string(),
    )
    .unwrap()
}

#[test]
fn missing_live_owners_are_explicitly_unavailable_without_synthetic_fallback() {
    let status = availability(None, None);
    assert!(!status.synthetic);
    assert!(status.local_reads);
    assert_eq!(
        status.chat.reason,
        Some(UnavailableReason::ProviderOwnerNotBound)
    );
    assert_eq!(
        status.search.reason,
        Some(UnavailableReason::SearchHostNotBound)
    );
    assert!(!status.chat.transport_bound && !status.search.transport_bound);
}

#[test]
fn suppliers_are_current_database_reads_and_deleted_records_are_not_context() {
    let temp = Temp::new();
    let store = temp.store();
    supplier(&store);
    let reply = local(
        &store,
        None,
        json!({"tool":"supplier_list","limit":20,"offset":0}),
    );
    assert_eq!(reply["records"][0]["payload"]["name"], "当前供应商");
    assert_eq!(reply["records"][0]["revision"], "1");
    assert_eq!(reply["outbound_authorized"], false);
    execute(
        &store,
        &command(
            "supplier-delete",
            None,
            1,
            Operation::SupplierDelete {
                supplier_id: "supplier-a".into(),
            },
        ),
    );
    assert_eq!(
        local(
            &store,
            None,
            json!({"tool":"supplier_list","limit":20,"offset":0})
        )["records"],
        json!([])
    );
    assert_eq!(
        read_business(
            &store,
            &ReadScope::current(&store, None).unwrap(),
            r#"{"tool":"supplier_get","id":"supplier-a"}"#
        )
        .unwrap_err(),
        ContractError::NotFound
    );
}

#[test]
fn tools_reject_writes_scope_injection_duplicate_keys_and_unbounded_pages() {
    let temp = Temp::new();
    let store = temp.store();
    let scope = ReadScope::current(&store, None).unwrap();
    for raw in [
        r#"{"tool":"supplier_delete","id":"x"}"#,
        r#"{"tool":"supplier_list","limit":20,"offset":0,"workspace_id":"other"}"#,
        r#"{"tool":"supplier_get","tool":"supplier_list","id":"x"}"#,
        r#"{"tool":"supplier_list","limit":51,"offset":0}"#,
        r#"{"tool":"paper_list","limit":20,"offset":0}"#,
    ] {
        assert!(read_business(&store, &scope, raw).is_err(), "{raw}");
    }
    assert!(store.suppliers(20, 0).unwrap().is_empty());
}

#[test]
fn old_epoch_read_scope_cannot_be_reused_after_service_restart() {
    let temp = Temp::new();
    let store = temp.store();
    let scope = ReadScope::current(&store, None).unwrap();
    drop(store);
    let reopened = BusinessStore::open_existing(&temp.path(), "workspace-a", "epoch-b").unwrap();
    assert_eq!(
        read_business(
            &reopened,
            &scope,
            r#"{"tool":"supplier_list","limit":20,"offset":0}"#
        )
        .unwrap_err(),
        ContractError::ScopeMismatch
    );
}

#[test]
fn newly_added_paper_is_read_from_selected_project_without_raw_json_or_blob_path() {
    let temp = Temp::new();
    let store = temp.store();
    for id in ["project-a", "project-b"] {
        execute(
            &store,
            &command(
                id,
                Some(id),
                0,
                Operation::ProjectCreate {
                    project_id: id.into(),
                    name: id.into(),
                },
            ),
        );
    }
    let upload = store.begin_upload("project-a").unwrap();
    store
        .append_chunk(&upload.upload_id, b"%PDF-1.4 synthetic\n%%EOF\n")
        .unwrap();
    let blob = store.finish_blob(&upload.upload_id, BlobKind::Pdf).unwrap();
    execute(
        &store,
        &command(
            "paper-create",
            Some("project-a"),
            0,
            Operation::PaperCreate {
                paper_id: "paper-a".into(),
                payload: PaperPayload {
                    title: "新增科研论文".into(),
                    authors: vec!["作者".into()],
                    year: Some(2026),
                    doi: None,
                    url: None,
                    notes: Some("PRIVATE RAW NOTES".into()),
                    attachment: blob.blob,
                    attachment_upload_id: Some(blob.upload_id),
                },
            },
        ),
    );
    let result = local(
        &store,
        Some("project-a"),
        json!({"tool":"paper_list","limit":20,"offset":0}),
    );
    assert_eq!(result["records"][0]["title"], "新增科研论文");
    assert_eq!(result["records"][0]["attachment_count"], 1);
    assert!(!result.to_string().contains("PRIVATE RAW NOTES"));
    assert!(result["records"][0].get("raw_json").is_none());
    assert_eq!(
        local(
            &store,
            Some("project-b"),
            json!({"tool":"paper_list","limit":20,"offset":0})
        )["records"],
        json!([])
    );
    assert!(read_business(
        &store,
        &ReadScope::current(&store, Some("project-b")).unwrap(),
        r#"{"tool":"paper_get","id":"paper-a"}"#
    )
    .is_err());
}

fn stream(answer: &str, usage: bool) -> Vec<u8> {
    let mut data = format!(
        "data: {}\n\n",
        json!({"choices":[{"index":0,"delta":{"content":answer},"finish_reason":"stop"}]})
    );
    if usage {
        data.push_str(&format!(
            "data: {}\n\n",
            json!({"choices":[],"usage":{"prompt_tokens":17,"completion_tokens":4}})
        ));
    }
    data.push_str("data: [DONE]\n\n");
    data.into_bytes()
}
#[test]
fn response_requires_full_terminal_answer_and_usage_not_http_success() {
    let bytes = stream("本地解析样本", true);
    let result = decode_answer_sse(&bytes, false).unwrap();
    assert_eq!(result.answer, "本地解析样本");
    assert_eq!((result.input_tokens, result.output_tokens), (17, 4));
    assert_eq!(
        decode_answer_sse(&stream("回答", false), false),
        Err("usage_unknown")
    );
    assert!(decode_answer_sse(&bytes[..bytes.len() - 4], false).is_err());
    assert!(decode_answer_sse(&bytes, true).is_err());
    assert!(decode_answer_sse(b"HTTP/1.1 200 OK\r\n\r\n", false).is_err());
    assert_eq!(
        decode_answer_sse(&stream("Bearer prohibited", true), false),
        Err("answer_disclosure_denied")
    );
    assert!(decode_answer_sse(&stream("", true), false).is_err());
}
