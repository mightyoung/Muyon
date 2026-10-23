// Verify the registered domain through the actual public library boundary.
use contract::*;
use development_drafts::*;
use muyon_core::development_drafts;
pub use muyon_core::{contract, services};
use serde_json::json;
use services::{drafts::*, types::*};

fn scope() -> ScopeRef {
    ScopeRef {
        scope: Scope {
            workspace_id: "workspace:one".into(),
            project_id: None,
        },
        account_id: Some("account:one".into()),
        scope_generation: Revision::new(1),
    }
}
fn draft() -> ConversationDraft {
    ConversationDraft::new(
        DraftRef {
            owner_plugin_id: OWNER_PLUGIN_ID.into(),
            draft_id: "draft:one".into(),
            scope: scope(),
            revision: Revision::new(0),
        },
        "conversation:one".into(),
    )
    .unwrap()
}
fn source() -> SourceBinding {
    let text = "离线保留草稿，修复返回丢失，支持多项目吗？";
    SourceBinding {
        conversation_id: "conversation:one".into(),
        message_id: "message:one".into(),
        message_revision: Revision::new(2),
        start: 0,
        end: text.len(),
        original_message: text.into(),
    }
}
fn item(id: &str, text: &str, kind: ItemKind) -> DraftItem {
    DraftItem {
        item_id: id.into(),
        kind,
        text: DraftText {
            text: text.into(),
            manually_edited: false,
        },
        sources: vec![source()],
    }
}
fn patch(name: Option<&str>, items: Vec<DraftItem>) -> DraftPatch {
    DraftPatch {
        project_name: name.map(str::to_owned),
        items,
    }
}
fn apply(draft: &mut ConversationDraft, patch: DraftPatch, manual: bool) {
    draft
        .apply(&draft.revision().clone(), patch, manual)
        .unwrap();
}
fn ready() -> ConversationDraft {
    let mut draft = draft();
    apply(&mut draft, patch(Some("离线项目"), vec![]), false);
    draft
        .choose_project(&draft.revision().clone(), "project:new".into(), true)
        .unwrap();
    draft
}
fn command() -> CommandEnvelope {
    let mut command = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: "intent:create".into(),
        scope: scope().scope,
        expected_revision: Revision::new(0),
        authority: AuthorityBinding {
            grant_id: "grant:one".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch:one".into(),
        },
        plan_id: "plan:one".into(),
        plan_digest: "a".repeat(64),
        command: Operation::ProjectCreate {
            project_id: "project:new".into(),
            name: "离线项目".into(),
        },
    };
    command.plan_digest = command.expected_plan_digest().unwrap();
    command
}
fn unknown() -> ExecutionResult {
    ExecutionResult {
        status: ExecutionStatus::Unknown,
        receipt: None,
        error: Some(ContractError::Unknown),
        recovery_action: RecoveryAction::QueryOriginal,
    }
}
fn committed(command: &CommandEnvelope) -> ExecutionResult {
    ExecutionResult {
        status: ExecutionStatus::Committed,
        receipt: Some(Receipt {
            protocol_version: 1,
            intent_id: command.intent_id.clone(),
            binding_digest: command.binding_digest().unwrap(),
            scope: command.scope.clone(),
            authority: command.authority.clone(),
            admission_id: Some("admission:one".into()),
            target_id: command.command.target_id().into(),
            revision: Revision::new(1),
            status: ExecutionStatus::Committed,
            result: json!({"created": true}),
        }),
        error: None,
        recovery_action: RecoveryAction::None,
    }
}
struct FakeHost {
    executions: Vec<CommandEnvelope>,
    lookups: Vec<CommandEnvelope>,
    result: ExecutionResult,
}
impl ProjectHost for FakeHost {
    fn query_original(&mut self, command: &CommandEnvelope) -> ExecutionResult {
        self.lookups.push(command.clone());
        self.result.clone()
    }
}
fn host() -> FakeHost {
    FakeHost {
        executions: vec![],
        lookups: vec![],
        result: unknown(),
    }
}
// Test harness only: the real adapter still needs durable marker save + host admission.
trait FakeRun {
    fn run_project(&mut self, host: &mut FakeHost) -> Result<ExecutionResult, ContractError>;
}
impl FakeRun for ConversationDraft {
    fn run_project(&mut self, host: &mut FakeHost) -> Result<ExecutionResult, ContractError> {
        match self.begin_project_dispatch() {
            Ok(command) => {
                host.executions.push(command);
                self.observe_project_result(host.result.clone())?;
                Ok(host.result.clone())
            }
            Err(ContractError::IntentConflict) => self.recover_project(host),
            Err(error) => Err(error),
        }
    }
}
fn restore(draft: &ConversationDraft) -> ConversationDraft {
    ConversationDraft::restore(
        &serde_json::to_string(&draft.envelope().unwrap()).unwrap(),
        &scope(),
    )
    .unwrap()
}

#[test]
fn incremental_intake_keeps_multiple_items_and_original_source() {
    let mut draft = draft();
    apply(
        &mut draft,
        patch(
            None,
            vec![
                item("requirement:one", "离线保留草稿", ItemKind::Requirement),
                item("bug:one", "返回时丢失", ItemKind::Bug),
                item("question:one", "支持多项目吗？", ItemKind::Question),
            ],
        ),
        false,
    );
    assert_eq!(draft.project(), &ProjectChoice::Unassigned);
    assert_eq!(draft.items().len(), 3);
    apply(&mut draft, patch(Some("离线项目"), vec![]), false);
    assert_eq!(draft.items().len(), 3);
    assert_eq!(draft.project_name().unwrap().text, "离线项目");
    for item in draft.items() {
        assert_eq!(item.sources, vec![source()]);
    }
    assert_eq!(restore(&draft), draft);
}

#[test]
fn ambiguous_projects_require_explicit_selection() {
    let mut draft = draft();
    draft
        .propose_projects(
            &Revision::new(0),
            vec!["project:a".into(), "project:b".into()],
        )
        .unwrap();
    assert!(draft
        .prepare_project(&draft.revision().clone(), command())
        .is_err());
    assert!(draft
        .choose_project(&draft.revision().clone(), "project:c".into(), false)
        .is_err());
    draft
        .choose_project(&draft.revision().clone(), "project:b".into(), false)
        .unwrap();
    assert_eq!(
        draft.project(),
        &ProjectChoice::Existing {
            project_id: "project:b".into()
        }
    );
    assert!(draft
        .prepare_project(&draft.revision().clone(), command())
        .is_err());
}

#[test]
fn manual_edits_get_visible_conflicts_and_are_never_silently_replaced() {
    let mut draft = draft();
    apply(
        &mut draft,
        patch(
            Some("手改项目"),
            vec![item("requirement:one", "手改需求", ItemKind::Requirement)],
        ),
        true,
    );
    let proposal = patch(
        Some("建议项目"),
        vec![item("requirement:one", "建议需求", ItemKind::Requirement)],
    );
    let before = draft.clone();
    let differences = draft.preview(draft.revision(), &proposal).unwrap();
    assert_eq!(differences.len(), 2);
    assert_eq!(differences[1].before.as_deref(), Some("手改需求"));
    assert_eq!(differences[1].after, "建议需求");
    assert!(differences.iter().all(|v| v.conflicts_with_manual_edit));
    assert_eq!(
        draft.apply(&draft.revision().clone(), proposal.clone(), false),
        Err(ContractError::RevisionConflict)
    );
    assert_eq!(draft, before);
    apply(&mut draft, proposal, true);
    assert!(draft.items()[0].text.manually_edited);
}

#[test]
fn stale_revision_rejects_whole_patch_and_preserves_current_work() {
    let mut draft = ready();
    let before = draft.clone();
    assert_eq!(
        draft.apply(&Revision::new(0), patch(Some("旧内容"), vec![]), true),
        Err(ContractError::RevisionConflict)
    );
    assert_eq!(draft, before);
}

#[test]
fn source_rebinding_and_cross_conversation_injection_are_rejected() {
    let mut draft = draft();
    let original = item("requirement:one", "需求", ItemKind::Requirement);
    apply(&mut draft, patch(None, vec![original.clone()]), false);
    let before = draft.clone();
    for mutate in [0, 1, 2, 3] {
        let mut changed = original.clone();
        match mutate {
            0 => changed.sources[0].conversation_id = "conversation:other".into(),
            1 => changed.sources[0].message_revision = Revision::new(3),
            2 => changed.sources[0].start = 1, // Inside a UTF-8 code point.
            _ => changed.kind = ItemKind::Bug,
        }
        assert!(draft
            .apply(&draft.revision().clone(), patch(None, vec![changed]), true)
            .is_err());
        assert_eq!(draft, before);
    }
}

#[test]
fn duplicate_items_and_empty_sources_do_not_partially_apply() {
    let mut draft = draft();
    let original = item("requirement:one", "需求", ItemKind::Requirement);
    assert!(draft
        .apply(
            &Revision::new(0),
            patch(None, vec![original.clone(), original.clone()]),
            false
        )
        .is_err());
    let mut missing = original;
    missing.sources.clear();
    assert!(draft
        .apply(&Revision::new(0), patch(Some("项目"), vec![missing]), false)
        .is_err());
    assert_eq!(draft, self::draft());
}

#[test]
fn requirement_and_bug_are_only_draft_content_and_host_receives_only_project_create() {
    let mut draft = ready();
    apply(
        &mut draft,
        patch(
            None,
            vec![
                item("requirement:one", "需求", ItemKind::Requirement),
                item("bug:one", "Bug", ItemKind::Bug),
            ],
        ),
        false,
    );
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    let mut host = host();
    host.result = committed(&command());
    draft.run_project(&mut host).unwrap();
    assert_eq!(host.executions, vec![command()]);
    assert_eq!(draft.items().len(), 2);
    draft.run_project(&mut host).unwrap();
    assert_eq!(host.executions.len(), 1);
    assert!(host.lookups.is_empty());
}

#[test]
fn unknown_repeated_click_and_serialized_recovery_only_query_original() {
    let mut draft = ready();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    let mut host = host();
    assert_eq!(
        draft.run_project(&mut host).unwrap().status,
        ExecutionStatus::Unknown
    );
    let mut draft = restore(&draft);
    draft.run_project(&mut host).unwrap();
    host.result = committed(&command());
    draft.run_project(&mut host).unwrap();
    draft.run_project(&mut host).unwrap();
    assert_eq!(host.executions, vec![command()]);
    assert_eq!(host.lookups, vec![command(), command()]);
    assert_eq!(restore(&draft), draft);
}

#[test]
fn malformed_or_wrong_receipt_keeps_original_request_query_only() {
    let mut draft = ready();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    let mut host = host();
    host.result = committed(&command());
    host.result.receipt.as_mut().unwrap().intent_id = "intent:wrong".into();
    assert_eq!(
        draft.run_project(&mut host),
        Err(ContractError::BindingMismatch)
    );
    let mut draft = restore(&draft);
    host.result = committed(&command());
    draft.run_project(&mut host).unwrap();
    assert_eq!(host.executions.len(), 1);
    assert_eq!(host.lookups, vec![command()]);
}

#[test]
fn editing_invalidates_prepared_command_and_dispatched_draft_is_frozen() {
    let mut draft = ready();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    apply(&mut draft, patch(Some("新名字"), vec![]), true);
    let mut host = host();
    assert_eq!(draft.run_project(&mut host), Err(ContractError::Required));
    assert!(draft
        .prepare_project(&draft.revision().clone(), command())
        .is_err());
    let mut draft = ready();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    draft.run_project(&mut host).unwrap();
    let before = draft.clone();
    assert_eq!(
        draft.apply(&draft.revision().clone(), patch(Some("覆盖"), vec![]), true),
        Err(ContractError::IntentConflict)
    );
    assert!(draft
        .prepare_project(&draft.revision().clone(), command())
        .is_err());
    assert_eq!(draft, before);
}

#[test]
fn save_ack_matches_exact_content_scope_intent_and_revision() {
    let mut draft = ready();
    let envelope = draft.envelope().unwrap();
    let intent = IntentId::parse("intent:save").unwrap();
    let mut reference = envelope.draft_ref.clone();
    reference.revision = reference.revision.next().unwrap();
    let ack = SaveAck {
        draft_ref: reference,
        original_intent_id: intent.clone(),
        content_digest: Digest::parse(&stable_digest(&envelope.content).unwrap()).unwrap(),
    };
    let mut changed = draft.clone();
    apply(&mut changed, patch(Some("后续手改"), vec![]), true);
    assert!(changed.acknowledge_save(&intent, &ack).is_err());
    assert!(draft
        .acknowledge_save(&IntentId::parse("intent:other").unwrap(), &ack)
        .is_err());
    draft.acknowledge_save(&intent, &ack).unwrap();
    assert_eq!(draft.stored_revision(), &ack.draft_ref.revision);
    assert!(draft.acknowledge_save(&intent, &ack).is_err());
}

#[test]
fn restore_rejects_schema_scope_unknown_fields_and_command_tampering() {
    let mut draft = ready();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    let wire = serde_json::to_value(draft.envelope().unwrap()).unwrap();
    for mutation in 0..5 {
        let mut changed = wire.clone();
        match mutation {
            0 => changed["schema_version"] = json!(2),
            1 => changed["draft_ref"]["scope"]["scope_generation"] = json!("2"),
            2 => changed["content"]["surprise"] = json!(true),
            3 => changed["content"]["submission"]["command"]["command"]["name"] = json!("替换"),
            _ => changed["draft_ref"]["owner_plugin_id"] = json!("bot"),
        }
        assert!(ConversationDraft::restore(&changed.to_string(), &scope()).is_err());
    }
    let raw = serde_json::to_string(&wire).unwrap();
    assert!(ConversationDraft::restore(
        &raw.replacen(
            "\"schema_version\":1",
            "\"schema_version\":1,\"schema_version\":1",
            1
        ),
        &scope()
    )
    .is_err());
}

#[test]
fn overflow_is_atomic_and_does_not_invalidate_preparation() {
    let mut wire = draft().envelope().unwrap();
    wire.content["edit_revision"] = json!(u64::MAX.to_string());
    let mut draft =
        ConversationDraft::restore(&serde_json::to_string(&wire).unwrap(), &scope()).unwrap();
    let before = draft.clone();
    assert_eq!(
        draft.apply(&Revision::new(u64::MAX), patch(Some("项目"), vec![]), false),
        Err(ContractError::InvalidRevision)
    );
    assert_eq!(draft, before);
}

#[test]
fn saved_dispatch_marker_before_host_call_recovers_by_lookup_even_without_result() {
    let mut draft = ready();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    let mut host = host();
    assert_eq!(
        draft.recover_project(&mut host),
        Err(ContractError::Required)
    );
    assert_eq!(draft.begin_project_dispatch().unwrap(), command());
    // Simulate restart after marker save and before the original host call.
    let mut draft = restore(&draft);
    assert_eq!(
        draft.begin_project_dispatch(),
        Err(ContractError::IntentConflict)
    );
    draft.recover_project(&mut host).unwrap();
    assert!(host.executions.is_empty());
    assert_eq!(host.lookups, vec![command()]);
}

#[test]
fn pending_then_terminal_rejection_or_cancellation_never_creates_again() {
    for terminal in [
        ExecutionResult {
            status: ExecutionStatus::Rejected,
            receipt: None,
            error: Some(ContractError::InvalidAuthority),
            recovery_action: RecoveryAction::None,
        },
        ExecutionResult {
            status: ExecutionStatus::Cancelled,
            receipt: None,
            error: Some(ContractError::Cancelled),
            recovery_action: RecoveryAction::None,
        },
    ] {
        let mut draft = ready();
        draft
            .prepare_project(&draft.revision().clone(), command())
            .unwrap();
        let mut host = host();
        host.result.status = ExecutionStatus::Pending;
        draft.run_project(&mut host).unwrap();
        host.result = terminal.clone();
        assert_eq!(draft.recover_project(&mut host).unwrap(), terminal);
        let mut draft = restore(&draft);
        assert_eq!(draft.run_project(&mut host).unwrap(), terminal);
        assert_eq!(host.executions.len(), 1);
        assert_eq!(host.lookups.len(), 1);
        assert!(draft.observe_project_result(unknown()).is_err());
    }
}

#[test]
fn project_scoped_draft_cannot_be_assigned_to_another_project() {
    let mut reference = draft().envelope().unwrap().draft_ref;
    reference.scope.scope.project_id = Some("project:a".into());
    let mut draft = ConversationDraft::new(reference, "conversation:one".into()).unwrap();
    let before = draft.clone();
    assert_eq!(
        draft.propose_projects(
            &Revision::new(0),
            vec!["project:a".into(), "project:b".into()]
        ),
        Err(ContractError::ScopeMismatch)
    );
    assert_eq!(
        draft.choose_project(&Revision::new(0), "project:b".into(), true),
        Err(ContractError::ScopeMismatch)
    );
    assert_eq!(draft, before);
}

#[test]
fn host_preparation_is_bound_to_project_name_id_and_scope() {
    for mutation in 0..3 {
        let mut draft = ready();
        let mut changed = command();
        match mutation {
            0 => changed.scope.workspace_id = "workspace:other".into(),
            1 => {
                changed.command = Operation::ProjectCreate {
                    project_id: "project:other".into(),
                    name: "离线项目".into(),
                }
            }
            _ => {
                changed.command = Operation::ProjectCreate {
                    project_id: "project:new".into(),
                    name: "替换名字".into(),
                }
            }
        }
        changed.plan_digest = changed.expected_plan_digest().unwrap();
        assert!(draft
            .prepare_project(&draft.revision().clone(), changed)
            .is_err());
        assert!(draft.observe_project_result(unknown()).is_err());
    }
}

#[test]
fn local_edits_preserve_storage_baseline_and_first_save_advances_once() {
    let mut draft = ready();
    let edited = draft.revision().clone();
    let envelope = draft.envelope().unwrap();
    assert_eq!(envelope.draft_ref.revision, Revision::new(0));
    let intent = IntentId::parse("intent:first-save").unwrap();
    let mut reference = envelope.draft_ref.clone();
    reference.revision = Revision::new(1);
    let ack = SaveAck {
        draft_ref: reference,
        original_intent_id: intent.clone(),
        content_digest: Digest::parse(&stable_digest(&envelope.content).unwrap()).unwrap(),
    };
    draft.acknowledge_save(&intent, &ack).unwrap();
    assert_eq!(
        draft.envelope().unwrap().draft_ref.revision,
        Revision::new(1)
    );
    assert_eq!(draft.revision(), &edited);
    assert_eq!(restore(&draft), draft);
    assert!(draft.acknowledge_save(&intent, &ack).is_err());
    assert_eq!(draft.revision(), &edited);
}

fn large_source(bytes: usize, character: char) -> SourceBinding {
    let mut source = source();
    source.original_message = character.to_string().repeat(bytes);
    source.start = 0;
    source.end = source.original_message.len();
    source
}

#[test]
fn oversized_source_batch_is_rejected_without_losing_prepared_state() {
    let mut draft = ready();
    draft
        .prepare_project(&draft.revision().clone(), command())
        .unwrap();
    let before = draft.clone();
    let mut proposed = item("requirement:large", "大批来源", ItemKind::Requirement);
    proposed.sources = vec![large_source(65_536, 'x'); 17];
    assert_eq!(
        draft.apply(
            &draft.revision().clone(),
            patch(None, vec![proposed]),
            false
        ),
        Err(ContractError::RawLimit)
    );
    assert_eq!(draft, before);
    assert_eq!(restore(&draft), draft);
}

#[test]
fn encoded_escaping_and_accumulated_edits_share_the_whole_envelope_limit() {
    let mut accumulated = draft();
    for index in 0..15 {
        let mut proposed = item(
            &format!("requirement:{index}"),
            "来源",
            ItemKind::Requirement,
        );
        proposed.sources = vec![large_source(65_536, 'x')];
        apply(&mut accumulated, patch(None, vec![proposed]), false);
    }
    let before = accumulated.clone();
    let mut proposed = item("requirement:overflow", "来源", ItemKind::Requirement);
    proposed.sources = vec![large_source(65_536, 'x')];
    assert_eq!(
        accumulated.apply(
            &accumulated.revision().clone(),
            patch(None, vec![proposed]),
            false
        ),
        Err(ContractError::RawLimit)
    );
    assert_eq!(accumulated, before);
    assert_eq!(restore(&accumulated), accumulated);

    let mut escaped = draft();
    let mut proposed = item("requirement:escaped", "来源", ItemKind::Requirement);
    proposed.sources = vec![large_source(65_536, '\0'); 3];
    assert_eq!(
        escaped.apply(
            &escaped.revision().clone(),
            patch(None, vec![proposed]),
            false
        ),
        Err(ContractError::RawLimit)
    );
    assert_eq!(escaped.revision(), &Revision::new(0));
}

#[test]
fn oversized_receipt_does_not_replace_query_only_original_marker() {
    let mut draft = ready();
    let command = command();
    draft
        .prepare_project(&draft.revision().clone(), command.clone())
        .unwrap();
    draft.begin_project_dispatch().unwrap();
    let before = draft.clone();
    let mut result = committed(&command);
    result.receipt.as_mut().unwrap().result = json!({"padding": "x".repeat(MAX_COMMAND_BYTES)});
    assert_eq!(
        draft.observe_project_result(result),
        Err(ContractError::RawLimit)
    );
    assert_eq!(draft, before);
    assert_eq!(restore(&draft), draft);
    assert_eq!(
        draft.begin_project_dispatch(),
        Err(ContractError::IntentConflict)
    );
}

#[test]
fn deeply_nested_receipt_is_rejected_without_losing_original_marker() {
    let mut draft = ready();
    let command = command();
    draft
        .prepare_project(&draft.revision().clone(), command.clone())
        .unwrap();
    draft.begin_project_dispatch().unwrap();
    let before = draft.clone();
    let mut nested = json!(null);
    for _ in 0..140 {
        nested = json!({"child": nested});
    }
    let mut result = committed(&command);
    result.receipt.as_mut().unwrap().result = nested;
    assert_eq!(
        draft.observe_project_result(result),
        Err(ContractError::InvalidPayload)
    );
    assert_eq!(draft, before);
    assert_eq!(restore(&draft), draft);
    assert_eq!(
        draft.begin_project_dispatch(),
        Err(ContractError::IntentConflict)
    );
}

#[test]
fn stored_revision_exhaustion_does_not_exhaust_local_editor_revision() {
    let original = draft();
    let mut envelope = original.envelope().unwrap();
    envelope.draft_ref.revision = Revision::new(u64::MAX);
    let mut restored = ConversationDraft::restore(
        &serde_json::to_string(&envelope).unwrap(),
        &envelope.draft_ref.scope,
    )
    .unwrap();
    apply(&mut restored, patch(Some("Local edit"), vec![]), false);
    assert_eq!(restored.stored_revision(), &Revision::new(u64::MAX));
    assert_eq!(restored.revision(), &Revision::new(1));
    assert_eq!(restore(&restored), restored);
}

#[test]
fn receipt_at_exact_envelope_limit_restores_and_next_byte_is_atomic() {
    let mut draft = ready();
    let mut initial = draft.envelope().unwrap();
    initial.draft_ref.revision = Revision::new(9);
    draft =
        ConversationDraft::restore(&serde_json::to_string(&initial).unwrap(), &scope()).unwrap();
    let command = command();
    draft
        .prepare_project(&draft.revision().clone(), command.clone())
        .unwrap();
    draft.begin_project_dispatch().unwrap();
    let before = draft.clone();
    let mut result = committed(&command);
    result.receipt.as_mut().unwrap().result = json!({"padding": ""});
    let mut prospective = draft.envelope().unwrap();
    prospective.content["submission"]["result"] = serde_json::to_value(&result).unwrap();
    let overhead = serde_json::to_vec(&prospective).unwrap().len();
    result.receipt.as_mut().unwrap().result =
        json!({"padding": "x".repeat(MAX_COMMAND_BYTES - overhead + 1)});
    assert_eq!(
        draft.observe_project_result(result.clone()),
        Err(ContractError::RawLimit)
    );
    assert_eq!(draft, before);
    result.receipt.as_mut().unwrap().result =
        json!({"padding": "x".repeat(MAX_COMMAND_BYTES - overhead)});
    draft.observe_project_result(result).unwrap();
    assert_eq!(
        serde_json::to_vec(&draft.envelope().unwrap())
            .unwrap()
            .len(),
        MAX_COMMAND_BYTES
    );
    assert_eq!(restore(&draft), draft);
    let before_ack = draft.clone();
    let envelope = draft.envelope().unwrap();
    let intent = IntentId::parse("intent:save-boundary").unwrap();
    let mut reference = envelope.draft_ref.clone();
    reference.revision = Revision::new(10);
    let ack = SaveAck {
        draft_ref: reference,
        original_intent_id: intent.clone(),
        content_digest: Digest::parse(&stable_digest(&envelope.content).unwrap()).unwrap(),
    };
    assert_eq!(
        draft.acknowledge_save(&intent, &ack),
        Err(ContractError::RawLimit)
    );
    assert_eq!(draft, before_ack);
}

#[test]
fn preparing_command_near_envelope_limit_is_atomic() {
    let mut draft = ready();
    let mut proposed = item("requirement:budget", "来源", ItemKind::Requirement);
    proposed.sources = vec![large_source(65_536, 'x'); 15];
    proposed.sources.push(large_source(1, 'x'));
    apply(&mut draft, patch(None, vec![proposed.clone()]), false);
    let spare = MAX_COMMAND_BYTES
        - serde_json::to_vec(&draft.envelope().unwrap())
            .unwrap()
            .len();
    // Replacing byte 1 also increases the byte-offset field from 1 to five digits.
    proposed.sources[15] = large_source(spare - 20, 'x');
    let mut draft = ready();
    apply(&mut draft, patch(None, vec![proposed]), false);
    let before = draft.clone();
    assert_eq!(
        draft.prepare_project(&draft.revision().clone(), command()),
        Err(ContractError::RawLimit)
    );
    assert_eq!(draft, before);
    assert_eq!(restore(&draft), draft);
}
