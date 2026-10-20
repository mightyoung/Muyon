//! Narrow model function calls. Scope and visible disclosure are host authority,
//! never model arguments. No tool here grants or commits a business write.
use super::{
    owner::{AgentOwner, AgentPlan, HostedCostVerifier, Result, MODEL},
    read_business, ReadScope, ReadTool,
};
use crate::{
    business::BusinessStore,
    contract::{decode_json, ExecutionStatus, Operation, Revision},
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
    TOOLS.iter().map(|name|{
        let parameters=match *name {
            "supplier_list"|"paper_list"=>json!({"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":50},"offset":{"type":"integer","minimum":0,"maximum":10000}},"required":["limit","offset"],"additionalProperties":false}),
            "supplier_get"|"paper_get"=>json!({"type":"object","properties":{"id":{"type":"string","minLength":1,"maxLength":128}},"required":["id"],"additionalProperties":false}),
            _=>json!({"type":"object","properties":{"operation":{"type":"object"},"expected_revision":{"type":"string","pattern":"^(0|[1-9][0-9]*)$"}},"required":["operation","expected_revision"],"additionalProperties":false}),
        };
        Ok(ToolDefinition{name:format!("product.{name}"),wire_name:format!("product_{name}"),parameters:wire_json::parse(parameters.to_string().as_bytes()).map_err(|_|"tool_catalog_invalid")?})
    }).collect()
}
pub fn catalog_json() -> Result<Value> {
    definitions()?.into_iter().map(|d|Ok(json!({"type":"function","function":{"name":d.wire_name,"parameters":decode_json(&d.parameters.encode()).map_err(|_|"tool_catalog_invalid")?}}))).collect::<Result<Vec<_>>>().map(Value::Array)
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
        let definition = definitions()?
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
        if self.name.ends_with("_suggest") {
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
        let defs = definitions()?;
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
