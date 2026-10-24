//! Narrow model function calls. Scope and visible disclosure are host authority,
//! never model arguments. No tool here grants or commits a business write.
use super::{
    owner::{AgentOwner, AgentPlan, HostedCostVerifier, Result, MODEL},
    read_business, ReadScope, ReadTool,
};
use crate::{
    business::BusinessStore,
    contract::{decode_json, ExecutionStatus, Operation, Revision},
    development_drafts::{
        ConversationDraft, DraftItem, DraftPatch, DraftText, ItemKind, SourceBinding,
    },
    services::{
        drafts::{validate_save_ack, DraftEnvelope, SaveAck},
        types::{IntentId, ScopeRef},
    },
};
use muyon_core_agent_lab::{
    identifier,
    model::{ModelRequest, ToolDefinition},
    wire_json,
    wire_provider::encode_registered_request,
};
use muyon_rust_agent_host_lab::ordinary_chat::check_text;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
fn hash(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|v| format!("{v:02x}"))
        .collect()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DevelopmentArguments {
    project_name: Option<String>,
    items: Vec<DevelopmentItem>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DevelopmentItem {
    kind: ItemKind,
    text: String,
}
fn development_arguments(value: &Value) -> Result<DevelopmentArguments> {
    if value.to_string().len() > 8192
        || !value
            .as_object()
            .is_some_and(|v| v.contains_key("project_name"))
    {
        return Err("tool_arguments_invalid");
    }
    let args: DevelopmentArguments =
        serde_json::from_value(value.clone()).map_err(|_| "tool_arguments_invalid")?;
    if args.items.is_empty() || args.items.len() > 32 {
        return Err("tool_arguments_limit");
    }
    if let Some(name) = &args.project_name {
        crate::contract::normalize_text(name, 200, true).map_err(|_| "tool_arguments_invalid")?;
        check_text(name).map_err(|_| "tool_arguments_invalid")?;
    }
    for item in &args.items {
        crate::contract::normalize_text(&item.text, 2000, true)
            .map_err(|_| "tool_arguments_invalid")?;
        check_text(&item.text).map_err(|_| "tool_arguments_invalid")?;
    }
    Ok(args)
}

/// An extraction proposal carries original source evidence, never write authority.
#[derive(Clone, Debug)]
pub struct DevelopmentProposal {
    pub request_id: String,
    pub conversation_id: String,
    pub call_ref: String,
    pub draft_id: String,
    pub patch: DraftPatch,
    pub digest: String,
}
impl Serialize for DevelopmentProposal {
    fn serialize<S: serde::Serializer>(
        &self,
        serializer: S,
    ) -> std::result::Result<S::Ok, S::Error> {
        json!({"request_id":self.request_id,"conversation_id":self.conversation_id,"call_ref":self.call_ref,"draft_id":self.draft_id,"digest":self.digest,
            "patch":{"project_name":self.patch.project_name,"items":self.patch.items}}).serialize(serializer)
    }
}

fn development_source(request: &str, conversation: &str, payload: &Value) -> Result<SourceBinding> {
    let messages = payload["messages"]
        .as_array()
        .ok_or("tool_original_invalid")?;
    let (index, user) = messages
        .iter()
        .enumerate()
        .rev()
        .find(|(_, m)| m["role"] == "user")
        .ok_or("tool_original_invalid")?;
    let text = user["content"]
        .as_str()
        .filter(|v| !v.is_empty())
        .ok_or("tool_original_invalid")?;
    Ok(SourceBinding {
        conversation_id: conversation.into(),
        message_id: format!("{request}:user:{index}"),
        message_revision: Revision::new(0),
        start: 0,
        end: text.len(),
        original_message: text.into(),
    })
}
/// Fixed before the host calls DraftStore. Recovery must use this envelope and
/// original intent; a currently edited draft is never a substitute.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DevelopmentAcceptance {
    pub request_id: String,
    pub conversation_id: String,
    pub call_ref: String,
    pub envelope: DraftEnvelope,
    pub save_intent: IntentId,
    pub review_digest: String,
    pub scope: ScopeRef,
    pub session: String,
    pub generation: String,
    pub epoch: String,
}

impl AgentOwner {
    pub fn development_proposal_review(
        &self,
        request: &str,
        context: &ToolsContext,
    ) -> Result<DevelopmentProposal> {
        let (call, row) = self.bound_call(request, context)?;
        if call.name != "product.development_draft_propose" {
            return Err("tool_not_development");
        }
        let args = development_arguments(&call.arguments)?;
        let payload = decode_json(field(&row, 5)?).map_err(|_| "tool_original_invalid")?;
        let conversation = field(&row, 1)?.to_owned();
        let source = development_source(request, &conversation, &payload)?;
        let items = args
            .items
            .into_iter()
            .enumerate()
            .map(|(index, item)| DraftItem {
                item_id: format!("{request}:item:{index}"),
                kind: item.kind,
                text: DraftText {
                    text: item.text,
                    manually_edited: false,
                },
                sources: vec![source.clone()],
            })
            .collect::<Vec<_>>();
        let digest = hash(json!({"request_id":request,"conversation_id":conversation,"call_ref":call.call_ref,"project_name":args.project_name,"items":items}).to_string().as_bytes());
        Ok(DevelopmentProposal {
            request_id: request.into(),
            conversation_id: conversation,
            call_ref: call.call_ref,
            draft_id: format!("development-model-{request}"),
            patch: DraftPatch {
                project_name: args.project_name,
                items,
            },
            digest,
        })
    }
    pub fn begin_development_acceptance_trusted(
        &self,
        request: &str,
        context: &ToolsContext,
        envelope: &DraftEnvelope,
        save_intent: &IntentId,
    ) -> Result<DevelopmentAcceptance> {
        let tx = db(self.tool_db().transaction())?;
        // Repeat acceptance is query-only and cannot replace the frozen bytes.
        if !db(self.tool_db().query(
            "SELECT request_id FROM tool_steps WHERE request_id=?",
            &[request],
        ))?
        .is_empty()
        {
            let row = self.tool_request(request)?;
            if self.tool_epoch() != context.binding.epoch
                || self.configuration()?.id != field(&row, 3)?
            {
                return Err("tool_scope_changed");
            }
            if field(&row, 10)? != "0"
                || !matches!(field(&row, 9)?, "tool_pending" | "tool_consumed")
            {
                return Err("tool_original_not_pending");
            }
            let step = self.check_binding(request, context)?;
            if !matches!(
                field(&step, 1)?,
                "development_accepting" | "development_accepted"
            ) {
                return Err("development_acceptance_conflict");
            }
            let original = self.development_acceptance_original(request)?;
            if original.envelope != *envelope || original.save_intent != *save_intent {
                return Err("development_acceptance_conflict");
            }
            db(tx.commit())?;
            return Ok(original);
        }
        let proposal = self.development_proposal_review(request, context)?;
        let scope = &envelope.draft_ref.scope;
        if scope.scope.workspace_id != context.binding.workspace
            || scope.scope.project_id != context.binding.project
            || envelope.draft_ref.draft_id != proposal.draft_id
            || envelope.draft_ref.revision != Revision::new(0)
        {
            return Err("development_envelope_mismatch");
        }
        let mut expected =
            ConversationDraft::new(envelope.draft_ref.clone(), proposal.conversation_id.clone())
                .map_err(|_| "development_envelope_invalid")?;
        expected
            .apply(&Revision::new(0), proposal.patch, false)
            .map_err(|_| "development_envelope_invalid")?;
        if expected
            .envelope()
            .map_err(|_| "development_envelope_invalid")?
            != *envelope
        {
            return Err("development_envelope_mismatch");
        }
        let acceptance = DevelopmentAcceptance {
            request_id: request.into(),
            conversation_id: proposal.conversation_id,
            call_ref: proposal.call_ref,
            envelope: envelope.clone(),
            save_intent: save_intent.clone(),
            review_digest: proposal.digest,
            scope: scope.clone(),
            session: context.binding.session.clone(),
            generation: context.binding.generation.clone(),
            epoch: context.binding.epoch.clone(),
        };
        let binding = serde_json::to_string(&context.binding).map_err(|_| "tool_scope_invalid")?;
        let bytes =
            serde_json::to_string(&acceptance).map_err(|_| "development_envelope_invalid")?;
        db(self.tool_db().exec("INSERT INTO tool_steps(request_id,binding,stage,review,digest,plan_intent) VALUES(?,?,'development_accepting',?,?,?)", &[request, &binding, &bytes, &acceptance.review_digest, save_intent.as_str()]))?;
        db(tx.commit())?;
        Ok(acceptance)
    }
    /// Read the immutable original only, including after session/config changes.
    /// The trusted host checks its scope and looks up DraftStore's original intent.
    pub fn development_acceptance_original(&self, request: &str) -> Result<DevelopmentAcceptance> {
        let rows = db(self.tool_db().query(
            "SELECT binding,stage,review,digest,plan_intent FROM tool_steps WHERE request_id=?",
            &[request],
        ))?;
        let step = rows.first().ok_or("development_acceptance_missing")?;
        if !matches!(
            field(step, 1)?,
            "development_accepting" | "development_accepted"
        ) {
            return Err("development_acceptance_missing");
        }
        let record: DevelopmentAcceptance =
            serde_json::from_str(field(step, 2)?).map_err(|_| "development_acceptance_invalid")?;
        let row = self.tool_request(request)?;
        let binding: Binding =
            serde_json::from_str(field(step, 0)?).map_err(|_| "tool_scope_invalid")?;
        if field(&row, 16)? != field(step, 0)?
            || record.request_id != request
            || record.conversation_id != field(&row, 1)?
            || record.scope != record.envelope.draft_ref.scope
            || record.scope.scope.workspace_id != self.workspace()
            || binding.workspace != self.workspace()
            || binding.project != record.scope.scope.project_id
            || binding.session != record.session
            || binding.generation != record.generation
            || binding.epoch != record.epoch
            || record.review_digest != field(step, 3)?
            || record.save_intent.as_str() != field(step, 4)?
        {
            return Err("development_acceptance_invalid");
        }
        Ok(record)
    }
    pub fn complete_development_acceptance_trusted(
        &self,
        request: &str,
        context: &ToolsContext,
        ack: &SaveAck,
    ) -> Result<()> {
        let row = self.tool_request(request)?;
        if self.tool_epoch() != context.binding.epoch || self.configuration()?.id != field(&row, 3)?
        {
            return Err("tool_scope_changed");
        }
        self.check_binding(request, context)?;
        self.complete_development_acceptance_original_trusted(request, ack)
    }
    /// Recovery records only a proven original save, including one made before a
    /// crash or cancellation. It does not save, apply, dispatch, or call a model.
    pub fn complete_development_acceptance_original_trusted(
        &self,
        request: &str,
        ack: &SaveAck,
    ) -> Result<()> {
        let tx = db(self.tool_db().transaction())?;
        let record = self.development_acceptance_original(request)?;
        validate_save_ack(
            &record.envelope,
            &record.envelope.draft_ref.revision,
            &record.save_intent,
            ack,
        )
        .map_err(|_| "development_save_ack_mismatch")?;
        let rows = db(self.tool_db().query(
            "SELECT stage,plan_binding FROM tool_steps WHERE request_id=?",
            &[request],
        ))?;
        let step = rows.first().ok_or("development_acceptance_missing")?;
        let encoded = serde_json::to_string(ack).map_err(|_| "development_save_ack_mismatch")?;
        if field(step, 0)? == "development_accepted" && field(step, 1)? != encoded {
            return Err("development_save_ack_mismatch");
        }
        let row = self.tool_request(request)?;
        if !matches!(
            field(&row, 9)?,
            "tool_pending" | "cancelled" | "tool_consumed"
        ) {
            return Err("tool_original_not_pending");
        }
        db(self.tool_db().exec(
            "UPDATE tool_steps SET stage='development_accepted',plan_binding=? WHERE request_id=?",
            &[&encoded, request],
        ))?;
        // Keep the original tool turn as evidence; never fabricate an assistant answer.
        db(self.tool_db().exec(
            "UPDATE requests SET status='tool_consumed' WHERE id=?",
            &[request],
        ))?;
        db(tx.commit())?;
        Ok(())
    }
    pub fn reject_development_proposal_trusted(
        &self,
        request: &str,
        context: &ToolsContext,
    ) -> Result<()> {
        let tx = db(self.tool_db().transaction())?;
        let proposal = self.development_proposal_review(request, context)?;
        if !db(self.tool_db().query(
            "SELECT request_id FROM tool_steps WHERE request_id=?",
            &[request],
        ))?
        .is_empty()
        {
            return Err("development_acceptance_conflict");
        }
        let binding = serde_json::to_string(&context.binding).map_err(|_| "tool_scope_invalid")?;
        db(self.tool_db().exec("INSERT INTO tool_steps(request_id,binding,stage,review,digest) VALUES(?,?,'development_rejected','null',?)", &[request, &binding, &proposal.digest]))?;
        db(self.tool_db().exec(
            "UPDATE requests SET status='tool_consumed' WHERE id=? AND status='tool_pending'",
            &[request],
        ))?;
        db(tx.commit())?;
        Ok(())
    }
}

#[cfg(test)]
mod development_source_tests {
    use super::*;
    #[test]
    fn immutable_payload_selects_last_user_even_when_assistant_or_tool_follows() {
        let payload = json!({"messages":[{"role":"user","content":"older"},{"role":"assistant","content":"answer"},{"role":"user","content":"原始开发需求"},{"role":"assistant","content":null},{"role":"tool","content":"not a source"}]});
        let source = development_source("request-a", "conversation-a", &payload).unwrap();
        assert_eq!(source.message_id, "request-a:user:2");
        assert_eq!(source.original_message, "原始开发需求");
        assert_eq!(source.end, "原始开发需求".len());
        assert!(development_source(
            "request-a",
            "conversation-a",
            &json!({"messages":[{"role":"assistant","content":"no user"}]})
        )
        .is_err());
    }
}
fn db<T>(r: crate::sqlite::Result<T>) -> Result<T> {
    r.map_err(|_| "agent_storage_unavailable")
}
fn field(row: &[Option<String>], i: usize) -> Result<&str> {
    row.get(i)
        .and_then(Option::as_deref)
        .ok_or("tool_step_invalid")
}
const TOOLS: &[&str] = &[
    "supplier_list",
    "supplier_get",
    "paper_list",
    "paper_get",
    "supplier_suggest",
    "paper_suggest",
];
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ToolCall {
    pub call_ref: String,
    pub name: String,
    pub arguments: Value,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Suggestion {
    operation: Operation,
    expected_revision: Revision,
}

pub fn definitions() -> Result<Vec<ToolDefinition>> {
    definitions_for(false)
}
fn definitions_for(development: bool) -> Result<Vec<ToolDefinition>> {
    let mut names = TOOLS.to_vec();
    if development {
        names.push("development_draft_propose");
    }
    names.iter().map(|name|{
        let parameters=match *name {
            "development_draft_propose"=>json!({"type":"object","properties":{"project_name":{"type":["string","null"],"maxLength":200},"items":{"type":"array","minItems":1,"maxItems":32,"items":{"type":"object","properties":{"kind":{"type":"string","enum":["requirement","bug","question"]},"text":{"type":"string","minLength":1,"maxLength":2000}},"required":["kind","text"],"additionalProperties":false}}},"required":["project_name","items"],"additionalProperties":false}),
            "supplier_list"|"paper_list"=>json!({"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":50},"offset":{"type":"integer","minimum":0,"maximum":10000}},"required":["limit","offset"],"additionalProperties":false}),
            "supplier_get"|"paper_get"=>json!({"type":"object","properties":{"id":{"type":"string","minLength":1,"maxLength":128}},"required":["id"],"additionalProperties":false}),
            _=>json!({"type":"object","properties":{"operation":{"type":"object"},"expected_revision":{"type":"string","pattern":"^(0|[1-9][0-9]*)$"}},"required":["operation","expected_revision"],"additionalProperties":false}),
        };
        Ok(ToolDefinition{name:format!("product.{name}"),wire_name:format!("product_{name}"),parameters:wire_json::parse(parameters.to_string().as_bytes()).map_err(|_|"tool_catalog_invalid")?})
    }).collect()
}
pub fn catalog_json() -> Result<Value> {
    catalog_json_for(false)
}
pub(super) fn catalog_json_for(development: bool) -> Result<Value> {
    definitions_for(development)?.into_iter().map(|d|Ok(json!({"type":"function","function":{"name":d.wire_name,"parameters":decode_json(&d.parameters.encode()).map_err(|_|"tool_catalog_invalid")?}}))).collect::<Result<Vec<_>>>().map(Value::Array)
}
impl ToolCall {
    pub fn parse(message: &Value) -> Result<Self> {
        if !message["content"].is_null() && message["content"] != "" {
            return Err("tool_mixed_turn");
        }
        let calls = message["tool_calls"]
            .as_array()
            .ok_or("tool_calls_invalid")?;
        if calls.len() != 1 {
            return Err("tool_calls_limit");
        }
        let call = &calls[0];
        let object = call.as_object().ok_or("tool_call_invalid")?;
        if object.len() != 3 || call["type"] != "function" {
            return Err("tool_call_invalid");
        }
        let call_ref = call["id"]
            .as_str()
            .filter(|v| identifier(v))
            .ok_or("tool_call_identity_invalid")?
            .to_owned();
        let function = call["function"]
            .as_object()
            .ok_or("tool_function_invalid")?;
        if function.len() != 2 {
            return Err("tool_function_invalid");
        }
        let wire = function["name"].as_str().ok_or("tool_name_invalid")?;
        let definition = definitions_for(true)?
            .into_iter()
            .find(|t| t.wire_name == wire)
            .ok_or("tool_not_allowed")?;
        let raw = function["arguments"]
            .as_str()
            .ok_or("tool_arguments_invalid")?;
        if raw.len() > 8192 {
            return Err("tool_arguments_limit");
        }
        let arguments = decode_json(raw).map_err(|_| "tool_arguments_invalid")?;
        let result = Self {
            call_ref,
            name: definition.name,
            arguments,
        };
        result.validate()?;
        Ok(result)
    }
    fn validate(&self) -> Result<()> {
        if self.name == "product.development_draft_propose" {
            development_arguments(&self.arguments)?;
        } else if self.name.ends_with("_suggest") {
            self.suggestion()?;
        } else {
            self.read_request()?;
        }
        Ok(())
    }
    fn read_request(&self) -> Result<String> {
        let name = self
            .name
            .strip_prefix("product.")
            .filter(|v| TOOLS.contains(v) && !v.ends_with("_suggest"))
            .ok_or("tool_not_read")?;
        let mut arguments = self
            .arguments
            .as_object()
            .ok_or("tool_arguments_invalid")?
            .clone();
        if arguments.contains_key("tool") {
            return Err("tool_arguments_invalid");
        }
        arguments.insert("tool".into(), Value::String(name.into()));
        let raw = Value::Object(arguments).to_string();
        let parsed: ReadTool = serde_json::from_str(&raw).map_err(|_| "tool_arguments_invalid")?;
        match parsed {
            ReadTool::SupplierList { limit, offset } | ReadTool::PaperList { limit, offset } => {
                if !(1..=50).contains(&limit) || offset > 10000 {
                    return Err("tool_arguments_limit");
                }
            }
            ReadTool::SupplierGet { id } | ReadTool::PaperGet { id } => {
                if id.is_empty()
                    || id.len() > 128
                    || !id
                        .bytes()
                        .all(|c| c.is_ascii_alphanumeric() || b"-_.:".contains(&c))
                {
                    return Err("tool_arguments_invalid");
                }
            }
        }
        Ok(raw)
    }
    fn suggestion(&self) -> Result<Suggestion> {
        let result: Suggestion = serde_json::from_value(self.arguments.clone())
            .map_err(|_| "tool_suggestion_invalid")?;
        let allowed = match self.name.as_str() {
            "product.supplier_suggest" => matches!(
                result.operation,
                Operation::SupplierCreate { .. }
                    | Operation::SupplierUpdate { .. }
                    | Operation::SupplierDelete { .. }
                    | Operation::SupplierRestore { .. }
            ),
            "product.paper_suggest" => matches!(result.operation, Operation::PaperCreate { .. }),
            _ => false,
        };
        if !allowed {
            return Err("tool_write_not_allowed");
        }
        let target = result.operation.target_id();
        if target.is_empty()
            || target.len() > 128
            || !target
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || b"-_.:".contains(&c))
        {
            return Err("tool_suggestion_invalid");
        }
        match &result.operation {
            Operation::SupplierCreate { payload, .. }
            | Operation::SupplierUpdate { payload, .. } => {
                payload.normalize().map_err(|_| "tool_suggestion_invalid")?;
            }
            Operation::PaperCreate { payload, .. } => {
                payload.validate().map_err(|_| "tool_suggestion_invalid")?
            }
            _ => {}
        }
        Ok(result)
    }
}

/// Construct only from the Service's current live lease/selected project. No
/// Deserialize implementation: models cannot supply scope or its generation.
pub struct ToolsContext {
    binding: Binding,
    scope: ReadScope,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct Binding {
    workspace: String,
    project: Option<String>,
    epoch: String,
    session: String,
    generation: String,
}
impl ToolsContext {
    pub fn current(
        store: &BusinessStore,
        session: &str,
        generation: &str,
        project: Option<&str>,
    ) -> Result<Self> {
        for value in [session, generation] {
            if value.is_empty() || value.len() > 128 || value.chars().any(char::is_control) {
                return Err("tool_scope_invalid");
            }
        }
        Ok(Self {
            binding: Binding {
                workspace: store.workspace_id().into(),
                project: project.map(str::to_owned),
                epoch: store.owner_epoch().into(),
                session: session.into(),
                generation: generation.into(),
            },
            scope: ReadScope::current(store, project).map_err(|_| "tool_scope_invalid")?,
        })
    }
}
#[derive(Clone, Debug, Serialize)]
pub struct DisclosureReview {
    pub request_id: String,
    pub values: Value,
    pub bytes: String,
    pub digest: String,
    pub purpose: String,
    pub scope: Value,
}
/// Host returns only a pure P04 plan handle and user-visible summary, never a
/// CommandEnvelope, grant, authority or execute callback.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PreparedSuggestion {
    pub plan_id: String,
    pub summary: String,
}

pub struct HostPreparedSuggestion {
    pub view: PreparedSuggestion,
    pub intent_id: String,
    pub binding_digest: String,
}

impl AgentOwner {
    pub fn bind_tool_scope_trusted(&self, request: &str, context: &ToolsContext) -> Result<()> {
        if self.workspace() != context.binding.workspace
            || self.tool_epoch() != context.binding.epoch
        {
            return Err("tool_scope_changed");
        }
        let tx = db(self.tool_db().transaction())?;
        let row = self.tool_request(request)?;
        if field(&row, 9)? != "prepared"
            || field(&row, 4)? != context.binding.epoch
            || self.configuration()?.id != field(&row, 3)?
        {
            return Err("tool_scope_binding_closed");
        }
        let binding = serde_json::to_string(&context.binding).map_err(|_| "tool_scope_invalid")?;
        if let Some(current) = &row[16] {
            if current != &binding {
                return Err("tool_scope_changed");
            }
        } else {
            db(self.tool_db().exec("UPDATE requests SET tool_binding=? WHERE id=? AND status='prepared' AND tool_binding IS NULL",&[&binding,request]))?;
        }
        db(tx.commit())?;
        Ok(())
    }
    fn bound_call(
        &self,
        request: &str,
        context: &ToolsContext,
    ) -> Result<(ToolCall, Vec<Option<String>>)> {
        if self.workspace() != context.binding.workspace
            || self.tool_epoch() != context.binding.epoch
        {
            return Err("tool_scope_changed");
        }
        let row = self.tool_request(request)?;
        let bound: Binding =
            serde_json::from_str(field(&row, 16)?).map_err(|_| "tool_scope_binding_missing")?;
        if bound != context.binding {
            return Err("tool_scope_changed");
        }
        if field(&row, 9)? != "tool_pending"
            || field(&row, 10)? != "0"
            || field(&row, 4)? != context.binding.epoch
            || self.configuration()?.id != field(&row, 3)?
        {
            return Err("tool_original_not_pending");
        }
        let value = decode_json(field(&row, 11)?).map_err(|_| "tool_turn_invalid")?;
        let call: ToolCall =
            serde_json::from_value(value["call"].clone()).map_err(|_| "tool_turn_invalid")?;
        call.validate()?;
        Ok((call, row))
    }
    fn check_binding(&self, request: &str, context: &ToolsContext) -> Result<Vec<Option<String>>> {
        let rows = db(self.tool_db().query(
            "SELECT binding,stage,review,digest,followup,plan_intent,plan_binding FROM tool_steps WHERE request_id=?",
            &[request],
        ))?;
        let row = rows.into_iter().next().ok_or("tool_review_required")?;
        let binding: Binding =
            serde_json::from_str(field(&row, 0)?).map_err(|_| "tool_step_invalid")?;
        if binding != context.binding {
            return Err("tool_scope_changed");
        }
        Ok(row)
    }
    pub fn review_tool_read(
        &self,
        store: &BusinessStore,
        context: &ToolsContext,
        request: &str,
    ) -> Result<DisclosureReview> {
        let (call, _) = self.bound_call(request, context)?;
        let value = read_business(store, &context.scope, &call.read_request()?)
            .map_err(|_| "tool_read_denied")?;
        let values = json!({"source":"current_local_business","records":value["records"],"project_id":context.binding.project});
        let bytes = values.to_string();
        if bytes.len() > 4096 {
            return Err("tool_disclosure_limit");
        }
        check_text(&bytes).map_err(|_| "tool_disclosure_denied")?;
        let digest = hash(bytes.as_bytes());
        let binding = serde_json::to_string(&context.binding).map_err(|_| "tool_scope_invalid")?;
        let tx = db(self.tool_db().transaction())?;
        let existing = db(self.tool_db().query(
            "SELECT request_id FROM tool_steps WHERE request_id=?",
            &[request],
        ))?;
        if existing.is_empty() {
            db(self.tool_db().exec("INSERT INTO tool_steps(request_id,binding,stage,review,digest) VALUES(?,?,'review',?,?)",&[request,&binding,&bytes,&digest]))?;
        } else {
            let row = self.check_binding(request, context)?;
            if field(&row, 1)? != "review" || field(&row, 3)? != digest {
                return Err("tool_review_changed");
            }
        }
        db(tx.commit())?;
        Ok(DisclosureReview {
            request_id: request.into(),
            values,
            bytes,
            digest,
            purpose: "model_tool_result".into(),
            scope: json!({"workspace_id":context.binding.workspace,"project_id":context.binding.project,"session":context.binding.session,"generation":context.binding.generation}),
        })
    }
    /// Separate visible disclosure approval, not a budget/grant. Re-reading
    /// current exact bytes prevents approval of stale supplier/paper fields.
    pub fn approve_tool_read_trusted(
        &self,
        store: &BusinessStore,
        context: &ToolsContext,
        request: &str,
        expected_digest: &str,
    ) -> Result<()> {
        let review = self.review_tool_read(store, context, request)?;
        if review.digest != expected_digest {
            return Err("tool_review_changed");
        }
        db(self.tool_db().exec("UPDATE tool_steps SET stage='approved' WHERE request_id=? AND stage='review' AND digest=?",&[request,expected_digest]))?;
        Ok(())
    }
    pub fn prepare_tool_suggestion<F>(
        &self,
        context: &ToolsContext,
        request: &str,
        prepare: F,
    ) -> Result<PreparedSuggestion>
    where
        F: FnOnce(Operation, Revision, Option<&str>) -> Result<HostPreparedSuggestion>,
    {
        let (call, _) = self.bound_call(request, context)?;
        let suggestion = call.suggestion()?;
        if matches!(suggestion.operation, Operation::PaperCreate { .. })
            && context.binding.project.is_none()
        {
            return Err("tool_project_required");
        }
        if !db(self.tool_db().query(
            "SELECT request_id FROM tool_steps WHERE request_id=?",
            &[request],
        ))?
        .is_empty()
        {
            return Err("tool_suggestion_already_prepared");
        }
        // Pure prepare only; no cross-database write transaction or execution.
        let plan = prepare(
            suggestion.operation,
            suggestion.expected_revision,
            context.binding.project.as_deref(),
        )?;
        if !identifier(&plan.view.plan_id.replace(':', "_"))
            || plan.view.summary.is_empty()
            || plan.view.summary.len() > 2000
        {
            return Err("tool_plan_invalid");
        }
        check_text(&plan.view.summary).map_err(|_| "tool_plan_disclosure_denied")?;
        let bytes = serde_json::to_string(&plan.view).map_err(|_| "tool_plan_invalid")?;
        let digest = hash(bytes.as_bytes());
        let binding = serde_json::to_string(&context.binding).map_err(|_| "tool_scope_invalid")?;
        db(self.tool_db().exec("INSERT INTO tool_steps(request_id,binding,stage,review,digest,plan_intent,plan_binding) VALUES(?,?,'suggestion',?,?,?,?)",&[request,&binding,&bytes,&digest,&plan.intent_id,&plan.binding_digest]))?;
        Ok(plan.view)
    }
    pub fn validate_tool_suggestion_trusted(
        &self,
        context: &ToolsContext,
        request: &str,
        plan_id: &str,
    ) -> Result<()> {
        self.bound_call(request, context)?;
        let step = self.check_binding(request, context)?;
        if field(&step, 1)? != "suggestion" {
            return Err("tool_suggestion_state_invalid");
        }
        let view: PreparedSuggestion =
            serde_json::from_str(field(&step, 2)?).map_err(|_| "tool_plan_invalid")?;
        if view.plan_id != plan_id {
            return Err("tool_plan_identity_mismatch");
        }
        Ok(())
    }
    fn verified_suggestion_result(
        &self,
        store: &BusinessStore,
        context: &ToolsContext,
        step: &[Option<String>],
    ) -> Result<Value> {
        let original = store
            .lookup(field(step, 5)?)
            .map_err(|_| "tool_business_original_unavailable")?;
        if original.status != ExecutionStatus::Committed {
            return Err("tool_business_original_not_committed");
        }
        let receipt = original.receipt.ok_or("tool_business_receipt_missing")?;
        if receipt.binding_digest != field(step, 6)?
            || receipt.scope.workspace_id != context.binding.workspace
            || receipt.scope.project_id != context.binding.project
        {
            return Err("tool_business_receipt_mismatch");
        }
        let value = decode_json(field(step, 2)?).map_err(|_| "tool_plan_invalid")?;
        let plan: PreparedSuggestion = serde_json::from_value(if value.get("plan").is_some() {
            value["plan"].clone()
        } else {
            value
        })
        .map_err(|_| "tool_plan_invalid")?;
        Ok(json!({"status":"committed","plan":plan}))
    }
    pub fn review_tool_suggestion_result(
        &self,
        store: &BusinessStore,
        context: &ToolsContext,
        request: &str,
        plan_id: &str,
    ) -> Result<DisclosureReview> {
        self.bound_call(request, context)?;
        let step = self.check_binding(request, context)?;
        if !matches!(field(&step, 1)?, "suggestion" | "suggestion_result_review") {
            return Err("tool_suggestion_state_invalid");
        }
        let value = self.verified_suggestion_result(store, context, &step)?;
        if value["plan"]["plan_id"] != plan_id {
            return Err("tool_plan_identity_mismatch");
        }
        let bytes = value.to_string();
        let digest = hash(bytes.as_bytes());
        db(self.tool_db().exec("UPDATE tool_steps SET stage='suggestion_result_review',review=?,digest=? WHERE request_id=?",&[&bytes,&digest,request]))?;
        Ok(DisclosureReview {
            request_id: request.into(),
            values: value,
            bytes,
            digest,
            purpose: "model_tool_result".into(),
            scope: json!({"workspace_id":context.binding.workspace,"project_id":context.binding.project,"session":context.binding.session,"generation":context.binding.generation}),
        })
    }
    pub fn approve_tool_suggestion_result_trusted(
        &self,
        store: &BusinessStore,
        context: &ToolsContext,
        request: &str,
        plan_id: &str,
        digest: &str,
    ) -> Result<()> {
        let review = self.review_tool_suggestion_result(store, context, request, plan_id)?;
        if review.digest != digest {
            return Err("tool_review_changed");
        }
        db(self.tool_db().exec("UPDATE tool_steps SET stage='suggestion_approved' WHERE request_id=? AND stage='suggestion_result_review' AND digest=?",&[request,digest]))?;
        Ok(())
    }
    pub fn prepare_tool_followup_trusted(
        &self,
        store: &BusinessStore,
        context: &ToolsContext,
        request: &str,
        verifier: Option<&dyn HostedCostVerifier>,
    ) -> Result<AgentPlan> {
        let (call, original) = self.bound_call(request, context)?;
        let step = self.check_binding(request, context)?;
        if step[4].is_some() {
            return Err("tool_followup_already_prepared");
        }
        let stage = field(&step, 1)?;
        if stage == "approved" {
            let value = read_business(store, &context.scope, &call.read_request()?)
                .map_err(|_| "tool_read_denied")?;
            let actual=json!({"source":"current_local_business","records":value["records"],"project_id":context.binding.project}).to_string();
            if hash(actual.as_bytes()) != field(&step, 3)? {
                return Err("tool_review_changed");
            }
        } else if stage == "suggestion_approved" {
            let actual = self
                .verified_suggestion_result(store, context, &step)?
                .to_string();
            if hash(actual.as_bytes()) != field(&step, 3)? {
                return Err("tool_review_changed");
            }
        } else {
            return Err("tool_visible_review_required");
        }
        let mut body = decode_json(field(&original, 5)?).map_err(|_| "tool_history_invalid")?;
        let messages = body["messages"]
            .as_array_mut()
            .ok_or("tool_history_invalid")?;
        messages.push(json!({"role":"assistant","content":null,"tool_calls":[{"id":call.call_ref,"type":"function","function":{"name":call.name,"arguments":call.arguments.to_string()}}]}));
        messages
            .push(json!({"role":"tool","tool_call_id":call.call_ref,"content":field(&step,2)?}));
        // The existing structural encoder proves pairing/name mapping; it does
        // not create authority. Product transport keeps its non-stream envelope.
        let history = wire_json::parse(body["messages"].to_string().as_bytes())
            .map_err(|_| "tool_history_invalid")?;
        let advertised = body["tools"].as_array().ok_or("tool_history_invalid")?;
        let defs: Vec<_> = definitions()?
            .into_iter()
            .filter(|definition| {
                advertised
                    .iter()
                    .any(|tool| tool["function"]["name"] == definition.wire_name)
            })
            .collect();
        if defs.is_empty() {
            return Err("tool_not_allowed");
        }
        let model_request = ModelRequest {
            task: "product".into(),
            attempt: request.into(),
            turn: 1,
            messages: vec![],
            tools: defs.iter().map(|d| d.name.clone()).collect(),
        };
        let encoded = encode_registered_request(&model_request, &history, &defs, MODEL)
            .map_err(|_| "tool_history_invalid")?;
        let mapped =
            decode_json(std::str::from_utf8(&encoded).map_err(|_| "tool_history_invalid")?)
                .map_err(|_| "tool_history_invalid")?;
        body["messages"] = mapped["messages"].clone();
        body["tools"] = mapped["tools"].clone();
        body["parallel_tool_calls"] = Value::Bool(false);
        let payload = body.to_string();
        // One DB transaction publishes the new request and consumes this step.
        let tx = db(self.tool_db().transaction())?;
        self.check_binding(request, context)?;
        let plan = self.tool_prepare_followup(field(&original, 1)?, payload, verifier)?;
        let binding = serde_json::to_string(&context.binding).map_err(|_| "tool_scope_invalid")?;
        db(self.tool_db().exec(
            "UPDATE requests SET tool_binding=? WHERE id=? AND status='prepared'",
            &[&binding, &plan.request_id],
        ))?;
        db(self.tool_db().exec(
            "UPDATE tool_steps SET followup=? WHERE request_id=? AND followup IS NULL",
            &[&plan.request_id, request],
        ))?;
        db(self.tool_db().exec(
            "UPDATE requests SET status='tool_consumed' WHERE id=? AND status='tool_pending'",
            &[request],
        ))?;
        db(tx.commit())?;
        Ok(plan)
    }
}
