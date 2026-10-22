use super::*;
use crate::artifacts::tests::{Fixture, human};
use crate::contract::*;
use std::time::{SystemTime, UNIX_EPOCH};
pub(super) fn expiry() -> u64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as u64 + 25_000 }
pub(super) fn fixture() -> (Fixture, BusinessStore, LocalAccess) {
    let f = Fixture::new(); let (s, _, _) = f.setup(); s.initialize_artifact_workflows_trusted().unwrap(); s.initialize_local_interactions_trusted().unwrap();
    let p = ArtifactProjectAccess { scope: Scope { workspace_id: "workspace".into(), project_id: Some("project".into()) }, actor_id: "actor".into(), project_revision: Revision::new(1), authority: AuthorityBinding { grant_id: "local-project".into(), generation: Revision::new(1), owner_epoch: "epoch".into() } };
    s.issue_artifact_project_grant_trusted(&p, &[ArtifactProjectOperation::LocalDraft, ArtifactProjectOperation::LocalSubmit, ArtifactProjectOperation::LocalFeedback, ArtifactProjectOperation::ReadOwnLocal], expiry()).unwrap();
    super::source_tests::create_source(&s);
    let proof=super::source_tests::resolved(&s,&p,ArtifactProjectOperation::LocalDraft);
    let reference = LocalObjectRef { object_id: "form".into(), target: proof.target(), component_id: "component".into(), component_revision: Revision::new(1), attempt_id: "attempt".into() };
    let a = LocalAccess { project: p, object: reference, binding_generation: Revision::new(1) };
    super::source_tests::issue(&s,&a, &LocalKind::Form(FormSpec { fields: vec![LocalField::Text, LocalField::Choice, LocalField::Selections], single_options: vec!["one".into(), "two".into()], multiple_options: vec!["a".into(), "b".into()] }), expiry()).unwrap();
    (f,s,a)
}
pub(super) fn patch(text: &str, expected: u64) -> LocalMutation { LocalMutation::Patch { expected: Revision::new(expected), changes: vec![FieldChange::Text { value: text.into() }], author: human().author } }
#[test]
fn draft_restart_cas_human_sticky_and_typed_allowlist() {
    let (f,s,a) = fixture();
    let saved = s.mutate_local_trusted("edit", &a, &patch("manual",0)).unwrap(); assert_eq!(saved.status, ArtifactSaveStatus::Committed);
    assert_eq!(s.mutate_local_trusted("edit", &a, &patch("manual",0)).unwrap(), saved);
    let mut suggest = patch("recommendation",1); if let LocalMutation::Patch { author, .. } = &mut suggest { *author = AnnotationAuthor::Ai { agent_id: "agent".into(), run_id: "run".into() }; }
    assert_eq!(s.mutate_local_trusted("suggest", &a, &suggest).unwrap().error, Some(ContractError::IntentConflict));
    assert_eq!(s.mutate_local_trusted("stale", &a, &patch("stale",0)).unwrap().error, Some(ContractError::RevisionConflict));
    let bad = LocalMutation::Patch { expected: Revision::new(1), changes: vec![FieldChange::Choice { value: Some("not-whitelisted".into()) }], author: human().author };
    assert_eq!(s.mutate_local_trusted("bad", &a, &bad).unwrap().error, Some(ContractError::InvalidPayload));
    drop(s); let s=f.open(); let state=s.read_local_form(&a).unwrap(); assert_eq!(state.values.text,"manual"); assert_eq!(state.manual_fields,vec![LocalField::Text]);
}
#[test]
fn confirmation_binds_original_values_and_edit_invalidates_preview() {
    let (_f,s,a) = fixture(); s.mutate_local_trusted("edit",&a,&patch("first",0)).unwrap();
    let preview=s.prepare_local_form_submit_trusted("submit",&a,&Revision::new(1)).unwrap();
    s.mutate_local_trusted("edit2",&a,&patch("second",1)).unwrap();
    assert_eq!(s.confirm_local_form_submit_trusted("submit",&a,&preview.digest).unwrap().error,Some(ContractError::RevisionConflict));
    let fresh=s.prepare_local_form_submit_trusted("submit2",&a,&Revision::new(2)).unwrap();
    let result=s.confirm_local_form_submit_trusted("submit2",&a,&fresh.digest).unwrap(); assert_eq!(result.status,ArtifactSaveStatus::Committed);
    assert_eq!(s.confirm_local_form_submit_trusted("submit2",&a,&fresh.digest).unwrap(),result);
    assert!(s.read_local_form(&a).unwrap().submitted_intent.is_some());
    assert_eq!(s.mutate_local_trusted("late",&a,&patch("overwrite",3)).unwrap().error,Some(ContractError::IntentConflict));
}
#[test]
fn feedback_exact_revision_permission_and_receipt_tail_revocation() {
    let (_f,s,a)=fixture(); let mut feedback=a.clone(); feedback.object.object_id="feedback".into();
    super::source_tests::issue(&s,&feedback,&LocalKind::Feedback,expiry()).unwrap();
    let op=LocalMutation::React { expected:Revision::new(0), value:Some(FeedbackValue::Helpful) };
    let saved=s.mutate_local_trusted("reaction",&feedback,&op).unwrap(); assert_eq!(saved.status,ArtifactSaveStatus::Committed);
    assert_eq!(s.read_local_feedback(&feedback).unwrap().value,Some(FeedbackValue::Helpful));
    let mut wrong=feedback.clone(); if let LocalTarget::Evidence { revision,.. }=&mut wrong.object.target { *revision=Revision::new(2); }
    assert!(s.read_local_feedback(&wrong).is_err());
    s.database().exec("CREATE TRIGGER revoke_local AFTER UPDATE ON artifact_local_intents_v1 WHEN NEW.status='committed' BEGIN UPDATE artifact_local_bindings_v1 SET active=0; END",&[]).unwrap();
    let changed=LocalMutation::React { expected:Revision::new(1),value:Some(FeedbackValue::NotHelpful) };
    let unknown=s.mutate_local_trusted("reaction2",&feedback,&changed).unwrap(); assert_eq!(unknown.status,ArtifactSaveStatus::Unknown); assert_eq!(unknown.recovery_action,RecoveryAction::QueryOriginal);
    assert_eq!(s.read_local_feedback(&feedback).unwrap().value,Some(FeedbackValue::Helpful));
    assert_eq!(s.mutate_local_trusted("reaction2",&feedback,&changed).unwrap().status,ArtifactSaveStatus::Unknown);
    assert_eq!(s.lookup_local_intent("reaction2",&a.project).unwrap().status,ArtifactSaveStatus::Unknown);
}
#[test]
fn pending_draft_save_is_locked_and_lookup_is_private_read_only() {
    let (_f,s,a)=fixture(); s.database().exec("CREATE TRIGGER fail_local BEFORE INSERT ON artifact_local_forms_v1 BEGIN SELECT RAISE(ABORT,'synthetic'); END",&[]).unwrap();
    assert_eq!(s.mutate_local_trusted("pending",&a,&patch("draft",0)).unwrap().status,ArtifactSaveStatus::Unknown);
    s.database().exec("DROP TRIGGER fail_local",&[]).unwrap();
    assert!(s.read_local_form(&a).unwrap().pending_intent.is_some());
    assert_eq!(s.mutate_local_trusted("other",&a,&patch("replacement",0)),Err(ContractError::IntentConflict));
    let before=s.database().query("SELECT * FROM artifact_local_intents_v1",&[]).unwrap();
    assert_eq!(s.lookup_local_intent("pending",&a.project).unwrap().status,ArtifactSaveStatus::Unknown);
    assert_eq!(s.database().query("SELECT * FROM artifact_local_intents_v1",&[]).unwrap(),before);
    s.database().exec("UPDATE artifact_project_grants_v1 SET active=0",&[]).unwrap(); assert!(s.read_local_form(&a).is_err());
}
#[test]
fn binding_and_project_generation_changes_invalidate_prepared_confirmation() {
    for rotate_project in [false,true] {
        let (_f,s,a)=fixture(); s.mutate_local_trusted("edit",&a,&patch("frozen",0)).unwrap();
        let preview=s.prepare_local_form_submit_trusted("submit",&a,&Revision::new(1)).unwrap();
        let tx=s.database().transaction().unwrap(); let kind=s.local_binding(&tx,&a,ArtifactProjectOperation::LocalDraft).unwrap(); drop(tx);
        let mut renewed=a.clone(); renewed.binding_generation=Revision::new(2);
        if rotate_project {renewed.project.authority.generation=Revision::new(2); s.issue_artifact_project_grant_trusted(&renewed.project,&[ArtifactProjectOperation::LocalDraft,ArtifactProjectOperation::LocalSubmit,ArtifactProjectOperation::LocalFeedback,ArtifactProjectOperation::ReadOwnLocal],expiry()).unwrap();}
        super::source_tests::issue(&s,&renewed,&kind,expiry()).unwrap();
        assert_eq!(s.confirm_local_form_submit_trusted("submit",&renewed,&preview.digest),Err(ContractError::BindingMismatch));
        assert_eq!(s.read_local_form(&renewed).unwrap().values.text,"frozen");
        assert!(s.read_local_form(&renewed).unwrap().submitted_intent.is_none());
        assert!(s.lookup_local_intent("submit",&renewed.project).unwrap().receipt.is_none());
    }
}
#[test]
fn fields_are_typed_and_zero_component_revision_matches_existing_ui_contract() {
    let (_f,s,a)=fixture(); let mut initial=a.clone(); initial.object.object_id="initial-component".into(); initial.object.component_revision=Revision::new(0);
    super::source_tests::issue(&s,&initial,&LocalKind::Form(FormSpec {fields:vec![LocalField::Text],single_options:vec![],multiple_options:vec![]}),expiry()).unwrap();
    assert_eq!(s.mutate_local_trusted("initial-save",&initial,&patch("local only",0)).unwrap().status,ArtifactSaveStatus::Committed);
    assert!(serde_json::from_str::<FieldChange>(r#"{"field":"invoke_tool","method":"send"}"#).is_err());
    assert!(serde_json::from_str::<FieldChange>(r#"{"field":"text","value":"hello","method":"execute"}"#).is_err());
    let mut bad=initial.clone(); bad.object.object_id="bad-source".into(); if let LocalTarget::Evidence {revision,..}=&mut bad.object.target{*revision=Revision::new(0);}
    assert_eq!(super::source_tests::issue(&s,&bad,&LocalKind::Feedback,expiry()),Err(ContractError::InvalidRevision));
}
#[test]
fn mutation_only_binding_can_be_revoked_without_read_permission() {
    let (_f,s,a)=fixture();
    for (kind,permission,id) in [(LocalKind::Feedback,ArtifactProjectOperation::LocalFeedback,"only-feedback"),(LocalKind::Form(FormSpec {fields:vec![LocalField::Text],single_options:vec![],multiple_options:vec![]}),ArtifactProjectOperation::LocalDraft,"only-draft")] {
        let mut limited=a.clone(); limited.object.object_id=id.into(); limited.project.authority.grant_id=id.into();
        s.issue_artifact_project_grant_trusted(&limited.project,&[permission],expiry()).unwrap();
        super::source_tests::issue(&s,&limited,&kind,expiry()).unwrap();
        assert!(s.read_local_form(&limited).is_err());
        s.revoke_local_binding_trusted(&limited).unwrap();
        let tx=s.database().transaction().unwrap(); assert!(s.local_binding(&tx,&limited,permission).is_err()); drop(tx);
    }
}
#[test]
fn explicit_choices_are_human_selections_and_suggestions_do_not_select() {
    let (_f,s,a)=fixture();
    let proposed=LocalMutation::Patch {expected:Revision::new(0),changes:vec![FieldChange::Choice {value:Some("one".into())}],author:AnnotationAuthor::Ai {agent_id:"agent".into(),run_id:"run".into()}};
    assert_eq!(s.mutate_local_trusted("recommend-choice",&a,&proposed).unwrap().error,Some(ContractError::UnsupportedOperation));
    assert_eq!(s.read_local_form(&a).unwrap().values.choice,None);
    let chosen=LocalMutation::Patch {expected:Revision::new(0),changes:vec![FieldChange::Choice {value:Some("two".into())},FieldChange::Selections {values:vec!["a".into(),"b".into()]}],author:human().author};
    assert_eq!(s.mutate_local_trusted("choose",&a,&chosen).unwrap().status,ArtifactSaveStatus::Committed);
    let state=s.read_local_form(&a).unwrap(); assert_eq!(state.values.choice,Some("two".into())); assert_eq!(state.values.selections,vec!["a","b"]);
    assert_eq!(state.manual_fields,vec![LocalField::Choice,LocalField::Selections]);
}
#[test]
fn actor_scope_epoch_generation_and_expiry_do_not_rebind_local_values() {
    let (_f,s,a)=fixture(); s.mutate_local_trusted("private-edit",&a,&patch("private",0)).unwrap();
    let mut other=a.clone(); other.project.actor_id="other-actor".into(); other.project.authority.grant_id="other-project-grant".into();
    s.issue_artifact_project_grant_trusted(&other.project,&[ArtifactProjectOperation::ReadOwnLocal],expiry()).unwrap();
    assert_eq!(s.lookup_local_intent("private-edit",&other.project).unwrap(),s.lookup_local_intent("absent",&other.project).unwrap());
    assert!(s.read_local_form(&other).is_err());
    let mut wrong=a.clone(); wrong.project.scope.project_id=Some("another-project".into()); assert!(s.read_local_form(&wrong).is_err());
    let mut wrong=a.clone(); wrong.project.authority.owner_epoch="old-epoch".into(); assert!(s.read_local_form(&wrong).is_err());
    let mut wrong=a.clone(); wrong.project.authority.generation=Revision::new(999); assert!(s.read_local_form(&wrong).is_err());
    let mut wrong=a.clone(); wrong.binding_generation=Revision::new(999); assert!(s.read_local_form(&wrong).is_err());
    s.database().exec("UPDATE artifact_local_bindings_v1 SET expires_at_ms='0'",&[]).unwrap(); assert!(s.read_local_form(&a).is_err());
}
#[test]
fn uncertain_preview_write_and_corrupt_original_review_never_submit() {
    let (_f,s,a)=fixture(); s.mutate_local_trusted("edit",&a,&patch("draft",0)).unwrap();
    s.database().exec("CREATE TRIGGER fail_review BEFORE INSERT ON artifact_local_reviews_v1 BEGIN SELECT RAISE(ABORT,'synthetic preview write'); END",&[]).unwrap();
    assert_eq!(s.prepare_local_form_submit_trusted("preview",&a,&Revision::new(1)),Err(ContractError::Unknown));
    assert_eq!(s.lookup_local_form_preview("preview",&a),Err(ContractError::NotFound));
    assert!(s.database().query("SELECT * FROM artifact_local_intents_v1 WHERE intent_id='preview'",&[]).unwrap().is_empty());
    s.database().exec("DROP TRIGGER fail_review",&[]).unwrap();
    let preview=s.prepare_local_form_submit_trusted("preview2",&a,&Revision::new(1)).unwrap();
    assert_eq!(s.lookup_local_form_preview("preview2",&a).unwrap(),preview);
    s.database().exec("UPDATE artifact_local_reviews_v1 SET request_json='{' WHERE intent_id='preview2'",&[]).unwrap();
    let result=s.confirm_local_form_submit_trusted("preview2",&a,&preview.digest).unwrap(); assert_eq!(result.status,ArtifactSaveStatus::Unknown); assert_eq!(result.recovery_action,RecoveryAction::QueryOriginal);
    assert_eq!(s.lookup_local_form_preview("preview2",&a),Err(ContractError::Unknown));
    assert!(s.read_local_form(&a).unwrap().submitted_intent.is_none());
}
#[test]
fn receipt_tail_policy_changes_keep_feedback_and_original_pending_atomic() {
    for mutation in ["UPDATE artifact_local_bindings_v1 SET expires_at_ms='0'","UPDATE artifact_local_bindings_v1 SET generation='999'","UPDATE artifact_project_grants_v1 SET active=0","UPDATE artifact_project_grants_v1 SET expires_at_ms='0'","UPDATE artifact_project_grants_v1 SET generation='999'"] {
        let (_f,s,a)=fixture(); let mut b=a.clone(); b.object.object_id="reaction-object".into();
        super::source_tests::issue(&s,&b,&LocalKind::Feedback,expiry()).unwrap();
        let first=LocalMutation::React {expected:Revision::new(0),value:Some(FeedbackValue::Helpful)}; s.mutate_local_trusted("first",&b,&first).unwrap();
        s.database().exec(&format!("CREATE TRIGGER late_policy AFTER UPDATE ON artifact_local_intents_v1 WHEN NEW.status='committed' BEGIN {mutation}; END"),&[]).unwrap();
        let next=LocalMutation::React {expected:Revision::new(1),value:Some(FeedbackValue::NotHelpful)};
        let result=s.mutate_local_trusted("late",&b,&next).unwrap(); assert_eq!(result.status,ArtifactSaveStatus::Unknown,"{mutation}");
        let state=s.read_local_feedback(&b).unwrap(); assert_eq!(state.value,Some(FeedbackValue::Helpful)); assert_eq!(state.pending_intent,Some("late".into()));
        assert_eq!(s.mutate_local_trusted("replacement",&b,&next),Err(ContractError::IntentConflict));
        assert_eq!(s.database().query("SELECT status,receipt_json FROM artifact_local_intents_v1 WHERE intent_id='late'",&[]).unwrap(),vec![vec![Some("pending".into()),None]]);
    }
}
#[test]
fn receipt_tail_cannot_change_the_allowed_field_policy() {
    let (_f,s,a)=fixture();
    let changed=LocalKind::Form(FormSpec {fields:vec![LocalField::Text],single_options:vec![],multiple_options:vec![]});
    let replacement=serde_json::to_string(&changed).unwrap();
    // Store a synthetic policy value in a test table so the trigger changes
    // valid policy JSON, not merely a malformed string rejected by decoding.
    s.database().exec("CREATE TABLE synthetic_policy(value TEXT)",&[]).unwrap(); s.database().exec("INSERT INTO synthetic_policy VALUES(?)",&[&replacement]).unwrap();
    s.database().exec("CREATE TRIGGER replace_policy AFTER UPDATE ON artifact_local_intents_v1 WHEN NEW.status='committed' BEGIN UPDATE artifact_local_bindings_v1 SET kind_json=(SELECT value FROM synthetic_policy); END",&[]).unwrap();
    let operation=LocalMutation::Patch {expected:Revision::new(0),changes:vec![FieldChange::Choice {value:Some("one".into())}],author:human().author};
    let result=s.mutate_local_trusted("policy-changed",&a,&operation).unwrap(); assert_eq!(result.status,ArtifactSaveStatus::Unknown);
    assert_eq!(s.read_local_form(&a).unwrap().values.choice,None);
    assert_eq!(s.lookup_local_intent("policy-changed",&a.project).unwrap().status,ArtifactSaveStatus::Unknown);
}
#[test]
fn binding_issue_checks_the_exact_requested_field_policy_after_its_write() {
    let (_f,s,a)=fixture(); let mut new=a.clone(); new.object.object_id="issue-policy".into();
    let requested=LocalKind::Form(FormSpec {fields:vec![LocalField::Text],single_options:vec![],multiple_options:vec![]});
    s.database().exec("CREATE TRIGGER issue_policy AFTER INSERT ON artifact_local_bindings_v1 WHEN NEW.object_id='issue-policy' BEGIN UPDATE artifact_local_bindings_v1 SET kind_json='{\"kind\":\"feedback\"}' WHERE object_id='issue-policy'; END",&[]).unwrap();
    // A different but valid kind is rejected after issuance; no row survives.
    assert!(super::source_tests::issue(&s,&new,&requested,expiry()).is_err());
    assert!(s.database().query("SELECT * FROM artifact_local_bindings_v1 WHERE object_id='issue-policy'",&[]).unwrap().is_empty());
}
#[test]
fn changed_allowlist_invalidates_frozen_confirmation_without_retargeting_values() {
    let (_f,s,a)=fixture(); s.mutate_local_trusted("draft",&a,&patch("frozen values",0)).unwrap();
    let preview=s.prepare_local_form_submit_trusted("confirm-policy",&a,&Revision::new(1)).unwrap();
    let changed=LocalKind::Form(FormSpec {fields:vec![LocalField::Text],single_options:vec![],multiple_options:vec![]});
    s.database().exec("UPDATE artifact_local_bindings_v1 SET kind_json=?",&[&serde_json::to_string(&changed).unwrap()]).unwrap();
    let result=s.confirm_local_form_submit_trusted("confirm-policy",&a,&preview.digest).unwrap();
    assert_eq!(result.status,ArtifactSaveStatus::Rejected); assert_eq!(result.error,Some(ContractError::BindingMismatch));
    let state=s.read_local_form(&a).unwrap(); assert!(state.submitted_intent.is_none()); assert_eq!(state.values.text,"frozen values");
}
#[test]
fn human_selection_does_not_relabel_suggested_text_as_human_content() {
    let (_f,s,a)=fixture(); let ai=AnnotationAuthor::Ai {agent_id:"agent".into(),run_id:"run".into()};
    let text=LocalMutation::Patch {expected:Revision::new(0),changes:vec![FieldChange::Text {value:"AI proposal".into()}],author:ai.clone()};
    s.mutate_local_trusted("suggest-text",&a,&text).unwrap();
    let choice=LocalMutation::Patch {expected:Revision::new(1),changes:vec![FieldChange::Choice {value:Some("one".into())}],author:human().author};
    s.mutate_local_trusted("human-choice",&a,&choice).unwrap();
    let preview=s.prepare_local_form_submit_trusted("save-local",&a,&Revision::new(2)).unwrap(); s.confirm_local_form_submit_trusted("save-local",&a,&preview.digest).unwrap();
    let state=s.read_local_form(&a).unwrap();
    assert_eq!(state.field_origins.iter().find(|entry|entry.field==LocalField::Text).unwrap().author,ai);
    assert!(!state.manual_fields.contains(&LocalField::Text)); assert!(state.manual_fields.contains(&LocalField::Choice));
}
