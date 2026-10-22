//! Product-specific durable outbound owner. No credentials or historical canary state.
use crate::{
    contract::{decode_json, Revision},
    sqlite::Db,
};
use muyon_rust_agent_host_lab::ordinary_chat::check_text;
use muyon_web_search_lab::{deepseek::DeepSeek, SearchProvider};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs::{File, OpenOptions},
    io::Read,
    os::fd::AsRawFd,
    path::{Path, PathBuf},
};
pub type Result<T> = std::result::Result<T, &'static str>;
pub const PRICE_REVISION: &str = "product-deepseek-cny-2-8-search5000-v1";
pub const MODEL: &str = "deepseek-flash";
pub const MAX_OUTPUT: u64 = 128;
const MAX_CAP: u64 = 1_000_000_000_000;
unsafe extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}
fn storage<T>(value: crate::sqlite::Result<T>) -> Result<T> {
    value.map_err(|_| "agent_storage_unavailable")
}
fn id(value: &str) -> Result<()> {
    if value.is_empty()
        || value.len() > 128
        || !value
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
    {
        Err("agent_identity_invalid")
    } else {
        Ok(())
    }
}
fn opaque() -> Result<String> {
    let mut b = [0u8; 16];
    File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut b))
        .map_err(|_| "agent_identity_unavailable")?;
    Ok(b.iter().map(|x| format!("{x:02x}")).collect())
}
fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|x| format!("{x:02x}"))
        .collect()
}
fn cell(row: &[Option<String>], index: usize) -> Result<&str> {
    row.get(index)
        .and_then(Option::as_deref)
        .ok_or("agent_storage_invalid")
}
fn number(value: &str) -> Result<u64> {
    value.parse().map_err(|_| "agent_storage_invalid")
}

/// Constructed by trusted compiled code, never deserialized from UI/model input.
pub struct HostedCostBound {
    input: u64,
    output: u64,
}
impl HostedCostBound {
    pub fn verified(input: u64, output: u64) -> Result<Self> {
        if input == 0 || input > 16384 || output != MAX_OUTPUT {
            Err("chat_cost_proof_invalid")
        } else {
            Ok(Self { input, output })
        }
    }
}
/// An implementation must prove hosted billing bounds for all actual payload
/// bytes and the pinned price revision. Reference tokenizer estimates are not
/// sufficient. Production defaults to no verifier; tests inject a local fixture.
pub trait HostedCostVerifier {
    fn prove(&self, payload: &[u8], price_revision: &str) -> Result<HostedCostBound>;
}
/// Trusted current-price authority, independently reviewed against the chosen
/// provider's exact per-request billing contract, including valid empty results.
/// Result-dependent billing needs a different reviewed contract; it must not be
/// inferred from result count. UI input is not this proof.
pub trait SearchPriceVerifier {
    fn prove(&self, endpoint: &str, payload: &[u8], price_revision: &str) -> Result<u64>;
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Settings {
    pub credential_generation: String,
    pub cap_micro_cny: Revision,
    pub max_calls: Revision,
    pub chat: bool,
    pub search: bool,
    pub price_revision: String,
}
#[derive(Clone, Debug, Serialize)]
pub struct Configuration {
    pub id: String,
    pub settings: Settings,
}
#[derive(Clone, Debug, Serialize)]
pub struct AgentPlan {
    pub request_id: String,
    pub conversation_id: String,
    pub purpose: String,
    pub configuration_id: String,
    pub payload_digest: String,
    pub reserved_micro_cny: Revision,
    pub send_allowed: bool,
    pub blocked_reason: Option<String>,
    /// Exact persisted body and destination reviewed before any reservation.
    pub outbound_preview: Value,
    pub outbound_endpoint: String,
}
/// Actual immutable request identity, reloaded and digest-checked by its owner.
/// No Deserialize or public constructor: a caller plan/JSON is not this fact.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct OriginalRequestBinding {
    request_id: String,
    workspace_id: String,
    conversation_id: String,
    purpose: String,
    configuration_id: String,
    request_epoch: String,
    payload_digest: String,
}
impl OriginalRequestBinding {
    pub fn request_id(&self) -> &str {
        &self.request_id
    }
    pub fn workspace_id(&self) -> &str {
        &self.workspace_id
    }
    pub fn conversation_id(&self) -> &str {
        &self.conversation_id
    }
    pub fn purpose(&self) -> &str {
        &self.purpose
    }
    pub fn configuration_id(&self) -> &str {
        &self.configuration_id
    }
    pub fn request_epoch(&self) -> &str {
        &self.request_epoch
    }
    pub fn payload_digest(&self) -> &str {
        &self.payload_digest
    }
}
#[derive(Clone, Debug, Serialize)]
pub struct Observation {
    pub request_id: String,
    pub status: String,
    pub reserved_micro_cny: Revision,
    pub charged_micro_cny: Revision,
    pub cancelled: bool,
    pub answer: Option<Value>,
    pub recovery_action: String,
    pub attempted: bool,
    pub failure_stage: Option<String>,
    pub http_status: Option<u16>,
    pub blocked_reason: Option<String>,
}
#[derive(Clone, Debug, Serialize)]
pub struct Budget {
    pub cap_micro_cny: Revision,
    pub held_micro_cny: Revision,
    pub charged_micro_cny: Revision,
    pub used_calls: Revision,
    pub max_calls: Revision,
}
/// Only the claimed dispatcher receives bytes; this is not a credential or grant.
#[derive(Clone, Debug, Serialize)]
pub struct Dispatch {
    pub request_id: String,
    pub configuration_id: String,
    pub credential_generation: String,
    pub purpose: String,
    pub payload: String,
}
struct DraftRequest {
    payload: String,
    reserved: u64,
    input: u64,
    reason: Option<String>,
}

pub struct AgentOwner {
    db: Db,
    workspace: String,
    epoch: String,
    _lock: File,
}
impl AgentOwner {
    pub fn initialize(path: &Path, workspace: &str) -> Result<()> {
        id(workspace)?;
        OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
            .map_err(|_| "agent_database_exists")?;
        let db = storage(Db::open(
            path.to_str().ok_or("agent_path_invalid")?,
            false,
            false,
        ))?;
        storage(db.query("PRAGMA journal_mode=WAL", &[]))?;
        storage(db.exec("PRAGMA synchronous=FULL", &[]))?;
        let tx = storage(db.transaction())?;
        storage(db.exec(
            "CREATE TABLE meta(workspace TEXT NOT NULL,version TEXT NOT NULL)",
            &[],
        ))?;
        storage(db.exec("INSERT INTO meta VALUES(?,'3')", &[workspace]))?;
        storage(db.exec("CREATE TABLE configuration(slot INTEGER PRIMARY KEY CHECK(slot=1),id TEXT NOT NULL,settings TEXT NOT NULL,epoch TEXT NOT NULL)",&[]))?;
        storage(db.exec("CREATE TABLE requests(id TEXT PRIMARY KEY,conversation TEXT NOT NULL,purpose TEXT NOT NULL,config TEXT NOT NULL,epoch TEXT NOT NULL,payload TEXT NOT NULL,digest TEXT NOT NULL,reserved INTEGER NOT NULL,charged INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL,cancelled INTEGER NOT NULL DEFAULT 0,answer TEXT,input_upper INTEGER NOT NULL,attempted INTEGER NOT NULL DEFAULT 0 CHECK(attempted IN (0,1)),failure_stage TEXT,http_status INTEGER,tool_binding TEXT)",&[]))?;
        storage(db.exec("CREATE TABLE tool_steps(request_id TEXT PRIMARY KEY,binding TEXT NOT NULL,stage TEXT NOT NULL,review TEXT NOT NULL,digest TEXT NOT NULL,followup TEXT,plan_intent TEXT,plan_binding TEXT)",&[]))?;
        storage(tx.commit())?;
        Ok(())
    }
    pub fn open(path: &Path, workspace: &str, epoch: &str) -> Result<Self> {
        id(workspace)?;
        id(epoch)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(PathBuf::from(format!("{}.owner.lock", path.display())))
            .map_err(|_| "agent_owner_unavailable")?;
        if unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
            return Err("agent_owner_busy");
        }
        let db = storage(Db::open(
            path.to_str().ok_or("agent_path_invalid")?,
            false,
            false,
        ))?;
        let rows = storage(db.query("SELECT workspace,version FROM meta", &[]))?;
        if rows.len() != 1 || cell(&rows[0], 0)? != workspace || cell(&rows[0], 1)? != "3" {
            return Err("agent_database_invalid");
        }
        storage(db.exec("PRAGMA synchronous=FULL", &[]))?;
        Ok(Self {
            db,
            workspace: workspace.into(),
            epoch: epoch.into(),
            _lock: lock,
        })
    }
    /// Call exclusively after visible user review. This creates only this
    /// product's configuration; changing it never resets cumulative spend/holds.
    pub fn configure_trusted(&self, settings: Settings) -> Result<Configuration> {
        id(&settings.credential_generation)?;
        let cap = settings.cap_micro_cny.value();
        let calls = settings.max_calls.value();
        if cap == 0
            || cap > MAX_CAP
            || calls == 0
            || calls > 100000
            || settings.price_revision != PRICE_REVISION
            || (!settings.chat && !settings.search)
        {
            return Err("agent_settings_invalid");
        }
        let tx = storage(self.db.transaction())?;
        let (held, charged, used) = self.totals()?;
        if held.checked_add(charged).ok_or("agent_budget_overflow")? > cap || used > calls {
            return Err("agent_budget_below_consumed");
        }
        let configuration = Configuration {
            id: opaque()?,
            settings,
        };
        let serialized =
            serde_json::to_string(&configuration.settings).map_err(|_| "agent_settings_invalid")?;
        storage(self.db.exec("INSERT INTO configuration VALUES(1,?,?,?) ON CONFLICT(slot) DO UPDATE SET id=excluded.id,settings=excluded.settings,epoch=excluded.epoch",&[&configuration.id,&serialized,&self.epoch]))?;
        storage(tx.commit())?;
        Ok(configuration)
    }
    pub fn configuration(&self) -> Result<Configuration> {
        let rows = storage(self.db.query(
            "SELECT id,settings,epoch FROM configuration WHERE slot=1",
            &[],
        ))?;
        let row = rows.first().ok_or("agent_configuration_unavailable")?;
        if cell(row, 2)? != self.epoch {
            return Err("agent_credential_reinstall_required");
        }
        Ok(Configuration {
            id: cell(row, 0)?.into(),
            settings: serde_json::from_str(cell(row, 1)?).map_err(|_| "agent_settings_invalid")?,
        })
    }
    pub fn budget(&self) -> Result<Budget> {
        // Recovery can disclose accounting without reinstalling credentials.
        // This read does not make an old configuration valid for dispatch.
        let rows = storage(
            self.db
                .query("SELECT settings FROM configuration WHERE slot=1", &[]),
        )?;
        let row = rows.first().ok_or("agent_configuration_unavailable")?;
        let settings: Settings =
            serde_json::from_str(cell(row, 0)?).map_err(|_| "agent_settings_invalid")?;
        let (held, charged, used) = self.totals()?;
        Ok(Budget {
            cap_micro_cny: settings.cap_micro_cny,
            held_micro_cny: Revision::new(held),
            charged_micro_cny: Revision::new(charged),
            used_calls: Revision::new(used),
            max_calls: settings.max_calls,
        })
    }
    fn totals(&self) -> Result<(u64, u64, u64)> {
        let rows=storage(self.db.query("SELECT COALESCE(SUM(CASE WHEN status IN ('reserved','unknown') THEN reserved ELSE 0 END),0),COALESCE(SUM(charged),0),COALESCE(SUM(CASE WHEN attempted=1 OR status='reserved' THEN 1 ELSE 0 END),0) FROM requests",&[]))?;
        Ok((
            number(cell(&rows[0], 0)?)?,
            number(cell(&rows[0], 1)?)?,
            number(cell(&rows[0], 2)?)?,
        ))
    }
    pub fn prepare_chat(
        &self,
        conversation: &str,
        text: &str,
        verifier: Option<&dyn HostedCostVerifier>,
    ) -> Result<AgentPlan> {
        self.prepare_chat_inner(conversation, text, verifier, None)
    }
    /// Host-selected child/skill tools are an actual capability subset.
    pub fn prepare_chat_restricted(
        &self,
        conversation: &str,
        text: &str,
        verifier: Option<&dyn HostedCostVerifier>,
        allowed: &[&str],
    ) -> Result<AgentPlan> {
        if allowed.is_empty() || allowed.len() > 6 {
            return Err("tool_not_allowed");
        }
        self.prepare_chat_inner(conversation, text, verifier, Some(allowed))
    }
    fn prepare_chat_inner(
        &self,
        conversation: &str,
        text: &str,
        verifier: Option<&dyn HostedCostVerifier>,
        allowed: Option<&[&str]>,
    ) -> Result<AgentPlan> {
        check_text(text).map_err(|_| "chat_text_denied")?;
        let configuration = self.configuration()?;
        if !configuration.settings.chat {
            return Err("chat_disabled");
        }
        id(conversation)?;
        let unresolved=storage(self.db.query("SELECT id FROM requests WHERE conversation=? AND status IN ('reserved','unknown','tool_pending') LIMIT 1",&[conversation]))?;
        if !unresolved.is_empty() {
            return Err("conversation_original_outcome_required");
        }
        let history=storage(self.db.query("SELECT payload,answer FROM requests WHERE conversation=? AND config=? AND purpose='chat' AND status='completed' AND cancelled=0 ORDER BY rowid DESC LIMIT 8",&[conversation,&configuration.id]))?;
        let mut messages = Vec::new();
        for row in history.iter().rev() {
            let previous = decode_json(cell(row, 0)?).map_err(|_| "chat_history_invalid")?;
            let user = previous["messages"]
                .as_array()
                .and_then(|a| a.last())
                .cloned()
                .ok_or("chat_history_invalid")?;
            if previous["messages"]
                .as_array()
                .is_some_and(|rows| rows.iter().any(|r| r["role"] == "tool"))
            {
                return Err("chat_tool_history_review_required");
            }
            let answer = decode_json(cell(row, 1)?).map_err(|_| "chat_history_invalid")?;
            let answer = answer["answer"].as_str().ok_or("chat_history_invalid")?;
            check_text(answer).map_err(|_| "chat_history_disclosure_denied")?;
            messages.push(user);
            messages.push(json!({"role":"assistant","content":answer}));
        }
        messages.push(json!({"role":"user","content":text}));
        let mut catalog = super::tools::catalog_json()?;
        if let Some(names) = allowed {
            let tools = catalog.as_array_mut().ok_or("tool_catalog_invalid")?;
            for name in names {
                if !tools
                    .iter()
                    .any(|tool| tool["function"]["name"] == format!("product_{name}"))
                {
                    return Err("tool_not_allowed");
                }
            }
            tools.retain(|tool| {
                names
                    .iter()
                    .any(|name| tool["function"]["name"] == format!("product_{name}"))
            });
        }
        let payload=json!({"model":MODEL,"messages":messages,"tools":catalog,"parallel_tool_calls":false,"n":1,"stream":false,"max_tokens":MAX_OUTPUT,"thinking":{"type":"disabled"}}).to_string();
        let proof = verifier
            .map(|v| v.prove(payload.as_bytes(), PRICE_REVISION))
            .transpose()?;
        let (reserved, input, reason) = match proof {
            Some(p) => (
                p.input
                    .checked_mul(2)
                    .and_then(|v| p.output.checked_mul(8).and_then(|n| v.checked_add(n)))
                    .ok_or("agent_budget_overflow")?,
                p.input,
                None,
            ),
            None => (0, 0, Some("hosted_cost_proof_unavailable".into())),
        };
        self.prepare(
            conversation,
            "chat",
            &configuration,
            DraftRequest {
                payload,
                reserved,
                input,
                reason,
            },
        )
    }
    pub fn prepare_search(&self, conversation: &str, query: &str, count: u64) -> Result<AgentPlan> {
        self.prepare_search_with_price(conversation, query, count, None)
    }
    pub fn prepare_search_with_price(
        &self,
        conversation: &str,
        query: &str,
        count: u64,
        verifier: Option<&dyn SearchPriceVerifier>,
    ) -> Result<AgentPlan> {
        check_text(query).map_err(|_| "search_query_denied")?;
        let configuration = self.configuration()?;
        if !configuration.settings.search {
            return Err("search_disabled");
        }
        let payload = DeepSeek
            .encode(query, count)
            .map_err(|_| "search_request_invalid")?
            .encode();
        let price = verifier
            .map(|v| v.prove(DeepSeek.endpoint(), payload.as_bytes(), PRICE_REVISION))
            .transpose()?;
        if price.is_some_and(|p| p == 0 || p > MAX_CAP) {
            return Err("search_price_proof_invalid");
        }
        self.prepare(
            conversation,
            "search",
            &configuration,
            DraftRequest {
                payload,
                reserved: price.unwrap_or(0),
                input: count,
                reason: price
                    .is_none()
                    .then(|| "search_price_proof_unavailable".into()),
            },
        )
    }
    fn prepare(
        &self,
        conversation: &str,
        purpose: &str,
        config: &Configuration,
        draft: DraftRequest,
    ) -> Result<AgentPlan> {
        let DraftRequest {
            payload,
            reserved,
            input,
            reason,
        } = draft;
        id(conversation)?;
        if payload.len() > 8192 {
            return Err("agent_payload_limit");
        }
        let request_id = opaque()?;
        let payload_digest = digest(payload.as_bytes());
        storage(self.db.exec("INSERT INTO requests(id,conversation,purpose,config,epoch,payload,digest,reserved,status,input_upper) VALUES(?,?,?,?,?,?,?,?,'prepared',?)",&[&request_id,conversation,purpose,&config.id,&self.epoch,&payload,&payload_digest,&reserved.to_string(),&input.to_string()]))?;
        Ok(AgentPlan {
            request_id,
            conversation_id: conversation.into(),
            purpose: purpose.into(),
            configuration_id: config.id.clone(),
            payload_digest,
            reserved_micro_cny: Revision::new(reserved),
            send_allowed: reason.is_none(),
            blocked_reason: reason,
            outbound_preview: decode_json(&payload).map_err(|_| "agent_payload_invalid")?,
            outbound_endpoint: if purpose == "search" {
                DeepSeek.endpoint().into()
            } else {
                "https://api.deepseek.com/chat/completions".into()
            },
        })
    }
    /// Durable reservation and one-use request identity. Only visible user
    /// confirmation may call this; model tools must not expose it.
    pub fn confirm_trusted(
        &self,
        request: &str,
        expected_configuration: &str,
    ) -> Result<Observation> {
        let tx = storage(self.db.transaction())?;
        let config = self.configuration()?;
        if config.id != expected_configuration {
            return Err("agent_configuration_changed");
        }
        let row = self.request(request)?;
        if cell(&row, 3)? != config.id || cell(&row, 4)? != self.epoch {
            return Err("agent_request_binding_changed");
        }
        if cell(&row, 9)? != "prepared" {
            return Err("agent_request_already_confirmed");
        }
        self.ensure_conversation_resolved_except(cell(&row, 1)?, request)?;
        let reserved = number(cell(&row, 7)?)?;
        if reserved == 0 {
            return Err("hosted_cost_proof_unavailable");
        }
        let (held, charged, used) = self.totals()?;
        if held
            .checked_add(charged)
            .and_then(|v| v.checked_add(reserved))
            .ok_or("agent_budget_overflow")?
            > config.settings.cap_micro_cny.value()
            || used >= config.settings.max_calls.value()
        {
            return Err("agent_budget_exhausted");
        }
        storage(self.db.exec(
            "UPDATE requests SET status='reserved' WHERE id=? AND status='prepared'",
            &[request],
        ))?;
        storage(tx.commit())?;
        self.lookup(request)
    }
    /// Commit unknown BEFORE the sole outbound attempt, retaining full hold even
    /// if process death occurs immediately afterwards. Never dispatch it twice.
    pub fn claim_dispatch(
        &self,
        request: &str,
        configuration: &str,
        generation: &str,
    ) -> Result<Dispatch> {
        let tx = storage(self.db.transaction())?;
        let config = self.configuration()?;
        let row = self.request(request)?;
        if config.id != configuration
            || config.settings.credential_generation != generation
            || cell(&row, 3)? != configuration
            || cell(&row, 4)? != self.epoch
            || cell(&row, 9)? != "reserved"
            || cell(&row, 10)? != "0"
        {
            return Err("agent_dispatch_denied");
        }
        self.ensure_conversation_resolved_except(cell(&row, 1)?, request)?;
        storage(self.db.exec(
            "UPDATE requests SET status='unknown',attempted=1 WHERE id=? AND status='reserved'",
            &[request],
        ))?;
        let dispatch = Dispatch {
            request_id: request.into(),
            configuration_id: configuration.into(),
            credential_generation: generation.into(),
            purpose: cell(&row, 2)?.into(),
            payload: cell(&row, 5)?.into(),
        };
        storage(tx.commit())?;
        Ok(dispatch)
    }
    pub fn dispatch_allowed(&self, request: &str, configuration: &str, generation: &str) -> bool {
        (|| -> Result<bool> {
            let config = self.configuration()?;
            let row = self.request(request)?;
            self.ensure_conversation_resolved_except(cell(&row, 1)?, request)?;
            Ok(config.id == configuration
                && config.settings.credential_generation == generation
                && cell(&row, 3)? == configuration
                && cell(&row, 4)? == self.epoch
                && cell(&row, 9)? == "unknown"
                && cell(&row, 10)? == "0")
        })()
        .unwrap_or(false)
    }
    pub fn cancel_trusted(&self, request: &str) -> Result<Observation> {
        let tx = storage(self.db.transaction())?;
        self.request(request)?;
        storage(self.db.exec("UPDATE requests SET cancelled=1,status=CASE WHEN status IN ('prepared','reserved','tool_pending') THEN 'cancelled' ELSE status END WHERE id=? AND status IN ('prepared','reserved','unknown','tool_pending')",&[request]))?;
        storage(tx.commit())?;
        self.lookup(request)
    }
    /// Full body validation precedes settlement. Invalid/truncated responses
    /// leave unknown and its hold unchanged; only exact recorded usage settles.
    pub fn settle_response(&self, request: &str, body: &str) -> Result<Observation> {
        if body.len() > 65536 {
            return Err("agent_response_limit");
        }
        let tx = storage(self.db.transaction())?;
        let row = self.request(request)?;
        if cell(&row, 9)? != "unknown" {
            return Err("agent_settlement_denied");
        }
        let value = decode_json(body).map_err(|_| "agent_response_invalid")?;
        let (answer, cost) = if cell(&row, 2)? == "search" {
            let results = DeepSeek
                .decode(body.as_bytes(), number(cell(&row, 12)?)?)
                .map_err(|_| "search_response_invalid")?;
            let charge = number(cell(&row, 7)?)?;
            (
                serde_json::from_str::<Value>(&muyon_web_search_lab::Json::Array(results).encode())
                    .map_err(|_| "search_response_invalid")?,
                charge,
            )
        } else {
            decode_chat_response(&value, number(cell(&row, 12)?)?)?
        };
        if cost > number(cell(&row, 7)?)? {
            return Err("agent_usage_exceeds_reservation");
        }
        if answer["turn"] == "tool_call" {
            let name = answer["call"]["name"]
                .as_str()
                .ok_or("tool_not_allowed")?
                .replace('.', "_");
            let payload = decode_json(cell(&row, 5)?).map_err(|_| "agent_response_invalid")?;
            if !payload["tools"]
                .as_array()
                .is_some_and(|tools| tools.iter().any(|tool| tool["function"]["name"] == name))
            {
                return Err("tool_not_allowed");
            }
        }
        let cancelled = cell(&row, 10)? == "1"
            || self
                .configuration()
                .map(|c| c.id != cell(&row, 3).unwrap_or(""))
                .unwrap_or(true);
        let serialized = if cancelled {
            "null".into()
        } else {
            answer.to_string()
        };
        storage(self.db.exec(
            "UPDATE requests SET status=?,charged=?,answer=? WHERE id=? AND status='unknown'",
            &[
                if cancelled {
                    "cancelled"
                } else if answer["turn"] == "tool_call" {
                    "tool_pending"
                } else {
                    "completed"
                },
                &cost.to_string(),
                &serialized,
                request,
            ],
        ))?;
        storage(tx.commit())?;
        self.lookup(request)
    }
    fn request(&self, request: &str) -> Result<Vec<Option<String>>> {
        id(request)?;
        let rows=storage(self.db.query("SELECT id,conversation,purpose,config,epoch,payload,digest,reserved,charged,status,cancelled,answer,input_upper,attempted,failure_stage,http_status,tool_binding FROM requests WHERE id=?",&[request]))?;
        rows.into_iter().next().ok_or("agent_request_not_found")
    }
    pub fn lookup(&self, request: &str) -> Result<Observation> {
        let row = self.request(request)?;
        let mut status = cell(&row, 9)?.to_owned();
        if cell(&row, 4)? != self.epoch && status == "reserved" {
            status = "unknown".into()
        }
        Ok(Observation {
            blocked_reason: if status == "prepared" && number(cell(&row, 7)?)? == 0 {
                Some(
                    if cell(&row, 2)? == "search" {
                        "search_price_proof_unavailable"
                    } else {
                        "hosted_cost_proof_unavailable"
                    }
                    .into(),
                )
            } else {
                None
            },
            attempted: cell(&row, 13)? == "1",
            failure_stage: row[14].clone(),
            http_status: row[15]
                .as_deref()
                .map(|v| v.parse().map_err(|_| "agent_storage_invalid"))
                .transpose()?,
            request_id: request.into(),
            reserved_micro_cny: Revision::new(number(cell(&row, 7)?)?),
            charged_micro_cny: Revision::new(number(cell(&row, 8)?)?),
            cancelled: cell(&row, 10)? == "1",
            answer: row[11]
                .as_deref()
                .map(serde_json::from_str)
                .transpose()
                .map_err(|_| "agent_storage_invalid")?,
            recovery_action: if status == "unknown" {
                "query_original"
            } else {
                "none"
            }
            .into(),
            status,
        })
    }
    /// Fixed diagnostics only; never settle, refund, retry or persist a body.
    pub fn record_diagnostic(
        &self,
        request: &str,
        stage: &str,
        http_status: Option<u16>,
    ) -> Result<()> {
        if !matches!(
            stage,
            "PREPARE"
                | "DNS"
                | "TCP_CONNECT"
                | "TLS_HANDSHAKE"
                | "AUTHORIZE_WRITE"
                | "WRITE"
                | "HTTP_STATUS"
                | "HTTP_HEADERS"
                | "HTTP_BODY"
                | "RESPONSE_VALIDATION"
                | "CANDIDATE_PERSIST"
                | "OWNER_HANDOFF"
                | "OWNER_AUTHORITY"
        ) || http_status.is_some_and(|c| !(100..=599).contains(&c))
        {
            return Err("agent_diagnostic_invalid");
        }
        let tx = storage(self.db.transaction())?;
        let row = self.request(request)?;
        if cell(&row, 9)? != "unknown" {
            return Err("agent_diagnostic_not_unknown");
        }
        match http_status {
            Some(code) => {
                storage(self.db.exec("UPDATE requests SET failure_stage=?,http_status=? WHERE id=? AND status='unknown'",&[stage,&code.to_string(),request]))?;
            }
            None => {
                storage(self.db.exec("UPDATE requests SET failure_stage=?,http_status=NULL WHERE id=? AND status='unknown'",&[stage,request]))?;
            }
        }
        storage(tx.commit())?;
        Ok(())
    }
    pub fn workspace(&self) -> &str {
        &self.workspace
    }
    /// Child conversations cannot bypass an unresolved root request. Host only.
    pub fn ensure_conversation_resolved(&self, conversation: &str) -> Result<()> {
        id(conversation)?;
        let rows = storage(self.db.query("SELECT id FROM requests WHERE conversation=? AND status IN ('reserved','unknown','tool_pending') LIMIT 1", &[conversation]))?;
        if !rows.is_empty() {
            return Err("conversation_original_outcome_required");
        }
        Ok(())
    }
    /// Revalidated for already-prepared plans and immediately before dispatch.
    fn ensure_conversation_resolved_except(&self, conversation: &str, request: &str) -> Result<()> {
        let rows = storage(self.db.query("SELECT id FROM requests WHERE conversation=? AND id<>? AND status IN ('reserved','unknown','tool_pending') LIMIT 1", &[conversation, request]))?;
        if !rows.is_empty() {
            return Err("conversation_original_outcome_required");
        }
        Ok(())
    }
    /// Read-only current owner identity, not an execution lease or permission.
    pub fn owner_epoch(&self) -> &str {
        &self.epoch
    }
    /// Reload the exact persisted canonical bytes. Configuration history/price,
    /// group/project/member and endpoint are not request columns and not invented.
    pub fn request_binding(&self, request: &str) -> Result<OriginalRequestBinding> {
        let row = self.request(request)?;
        if cell(&row, 0)? != request || digest(cell(&row, 5)?.as_bytes()) != cell(&row, 6)? {
            return Err("agent_request_binding_mismatch");
        }
        for value in [
            cell(&row, 1)?,
            cell(&row, 2)?,
            cell(&row, 3)?,
            cell(&row, 4)?,
        ] {
            id(value)?;
        }
        Ok(OriginalRequestBinding {
            request_id: request.into(),
            workspace_id: self.workspace.clone(),
            conversation_id: cell(&row, 1)?.into(),
            purpose: cell(&row, 2)?.into(),
            configuration_id: cell(&row, 3)?.into(),
            request_epoch: cell(&row, 4)?.into(),
            payload_digest: cell(&row, 6)?.into(),
        })
    }
    /// Host-only routing identity, never sourced from action/model JSON.
    pub fn request_conversation(&self, request: &str) -> Result<String> {
        Ok(cell(&self.request(request)?, 1)?.to_owned())
    }
    pub fn ensure_request_resolved(&self, request: &str) -> Result<()> {
        self.ensure_conversation_resolved_except(&self.request_conversation(request)?, request)
    }
    /// Follow only durable host-created edges, never caller-provided request lists.
    pub fn request_chain(&self, first: &str) -> Result<Vec<Observation>> {
        let mut next = first.to_owned();
        let first_row = self.request(first)?;
        let conversation = cell(&first_row, 1)?;
        let configuration = cell(&first_row, 3)?;
        let mut observations: Vec<Observation> = Vec::new();
        loop {
            if observations.len() >= 32 || observations.iter().any(|o| o.request_id == next) {
                return Err("tool_chain_limit");
            }
            let row = self.request(&next)?;
            if cell(&row, 1)? != conversation || cell(&row, 3)? != configuration {
                return Err("tool_history_invalid");
            }
            observations.push(self.lookup(&next)?);
            let rows = storage(self.db.query(
                "SELECT followup FROM tool_steps WHERE request_id=?",
                &[&next],
            ))?;
            match rows
                .first()
                .and_then(|row| row.first())
                .and_then(Option::as_deref)
            {
                Some(value) => next = value.into(),
                None => break,
            }
        }
        Ok(observations)
    }
    pub(super) fn tool_db(&self) -> &Db {
        &self.db
    }
    pub(super) fn tool_epoch(&self) -> &str {
        &self.epoch
    }
    pub(super) fn tool_request(&self, request: &str) -> Result<Vec<Option<String>>> {
        self.request(request)
    }
    pub(super) fn tool_prepare_followup(
        &self,
        conversation: &str,
        payload: String,
        verifier: Option<&dyn HostedCostVerifier>,
    ) -> Result<AgentPlan> {
        let body = decode_json(&payload).map_err(|_| "tool_history_invalid")?;
        if body["tools"]
            .as_array()
            .is_some_and(|tools| tools.len() < 6)
        {
            let rows = storage(self.db.query(
                "SELECT COUNT(*) FROM requests WHERE conversation=?",
                &[conversation],
            ))?;
            if number(cell(rows.first().ok_or("tool_history_invalid")?, 0)?)? >= 32 {
                return Err("tool_chain_limit");
            }
        }
        let configuration = self.configuration()?;
        let proof = verifier
            .map(|v| v.prove(payload.as_bytes(), PRICE_REVISION))
            .transpose()?;
        let (reserved, input, reason) = match proof {
            Some(p) => (
                p.input
                    .checked_mul(2)
                    .and_then(|v| p.output.checked_mul(8).and_then(|n| v.checked_add(n)))
                    .ok_or("agent_budget_overflow")?,
                p.input,
                None,
            ),
            None => (0, 0, Some("hosted_cost_proof_unavailable".into())),
        };
        self.prepare(
            conversation,
            "chat",
            &configuration,
            DraftRequest {
                payload,
                reserved,
                input,
                reason,
            },
        )
    }
}
impl Drop for AgentOwner {
    fn drop(&mut self) {
        unsafe {
            flock(self._lock.as_raw_fd(), 8);
        }
    }
}

fn unsigned(value: &Value) -> Result<u64> {
    value.as_u64().ok_or("chat_usage_invalid")
}
fn decode_chat_response(value: &Value, input_bound: u64) -> Result<(Value, u64)> {
    if value["model"] != MODEL && value["model"] != "DeepSeek-V4.1-Flash-1017" {
        return Err("chat_model_mismatch");
    }
    if value["id"]
        .as_str()
        .is_none_or(|v| v.is_empty() || v.len() > 512)
    {
        return Err("chat_response_identity_invalid");
    }
    let choices = value["choices"].as_array().ok_or("chat_choices_invalid")?;
    if choices.len() != 1
        || choices[0]["index"] != 0
        || !matches!(
            choices[0]["finish_reason"].as_str(),
            Some("stop" | "tool_calls")
        )
    {
        return Err("chat_answer_incomplete");
    }
    let message = &choices[0]["message"];
    if message["role"] != "assistant"
        || !message["function_call"].is_null()
        || (!message["reasoning_content"].is_null() && message["reasoning_content"] != "")
    {
        return Err("chat_unsupported_turn");
    }
    let usage = &value["usage"];
    let input = unsigned(&usage["prompt_tokens"])?;
    let output = unsigned(&usage["completion_tokens"])?;
    if input == 0
        || input > input_bound
        || output == 0
        || output > MAX_OUTPUT
        || unsigned(&usage["total_tokens"])?
            != input.checked_add(output).ok_or("chat_usage_invalid")?
    {
        return Err("chat_usage_invalid");
    }
    if usage["completion_tokens_details"]
        .get("reasoning_tokens")
        .is_some_and(|v| v != 0)
    {
        return Err("chat_reasoning_unsupported");
    }
    let cost = input
        .checked_mul(2)
        .and_then(|v| output.checked_mul(8).and_then(|n| v.checked_add(n)))
        .ok_or("chat_usage_invalid")?;
    if choices[0]["finish_reason"] == "tool_calls" {
        let call = super::tools::ToolCall::parse(message)?;
        return Ok((
            json!({"turn":"tool_call","call":call,"input_tokens":input.to_string(),"output_tokens":output.to_string(),"provider_request_id":value["id"],"synthetic":false}),
            cost,
        ));
    }
    if !message["tool_calls"].is_null() {
        return Err("chat_unsupported_turn");
    }
    let answer = message["content"].as_str().ok_or("chat_answer_invalid")?;
    check_text(answer).map_err(|_| "chat_answer_denied")?;
    Ok((
        json!({"answer":answer,"input_tokens":input.to_string(),"output_tokens":output.to_string(),"provider_request_id":value["id"],"synthetic":false}),
        cost,
    ))
}
