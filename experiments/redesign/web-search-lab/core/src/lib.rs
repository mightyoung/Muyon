//! Independent, provider-neutral WebSearch composition. No socket or secret-value API.
//! Install into the existing native registry; only a trusted durable owner may send.
pub use muyon_plugin_contract_lab::{object, parse, string, Json, Result};
pub mod deepseek;
pub mod runtime;
use muyon_core_agent_lab::policy::{authorize, Decision, HostFacts};
use muyon_rust_agent_host_lab::service_provider::CredentialHandle;
use std::rc::Rc;

pub fn request(query: &str, count: u64) -> Result<Json> {
    if query.trim().is_empty() || query.chars().count() > 128 || !(1..=50).contains(&count) {
        return Err("search_request_invalid".into());
    }
    Ok(object([
        ("query", string(query)),
        ("count", Json::Number(count.to_string())),
        ("need_content", Json::Bool(false)),
    ]))
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Money {
    pub currency: String,
    pub micros: u64,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchConfig {
    pub enabled: bool,
    pub id: String,
    pub provider: String,
    pub revision: String,
    pub policy_revision: String,
    pub endpoint: String,
    pub endpoint_identity: String,
    pub credential_ref: String,
    pub credential_generation: u64,
    /// Exact price/currency cap; independent of any model token or chat budget.
    pub price: Money,
    /// Muyon resource bound, not a documented server maximum.
    pub max_response_bytes: usize,
}
impl Default for SearchConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            id: String::new(),
            provider: String::new(),
            revision: String::new(),
            policy_revision: String::new(),
            endpoint: String::new(),
            endpoint_identity: String::new(),
            credential_ref: String::new(),
            credential_generation: 0,
            price: Money {
                currency: String::new(),
                micros: 0,
            },
            max_response_bytes: 32768,
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Invocation {
    pub task: String,
    pub attempt: String,
    pub scope: String,
    pub turn: u64,
    pub call_ref: String,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchCall {
    pub config: SearchConfig,
    pub invocation: Invocation,
    pub connection: Json,
    pub payload: Vec<u8>,
    pub max_cost: Money,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Settlement {
    Nonempty,
    Empty,
    Failed,
    Unknown,
}
/// No body/error text for uncertain handoff. A final owner may report a definite
/// pre-send refusal only after proving its durable attempt never admitted send.
pub enum Exchange {
    NotSent,
    Unknown,
    Http {
        status: u16,
        content_type: String,
        body: Vec<u8>,
    },
}
/// Implemented by the same trusted owner as the durable budget/outbound ledger.
/// Default denies; this crate cannot open connections or resolve secret bytes.
pub trait SearchHost {
    fn current(&self) -> Result<Option<SearchConfig>> {
        Ok(None)
    }
    /// Local adapter installation only, never a billable availability probe.
    fn transport_ready(&self, _config: &SearchConfig) -> bool {
        false
    }
    fn handle(&self, _config: &SearchConfig) -> Result<CredentialHandle> {
        Err("search_credential_unavailable".into())
    }
    /// Review ALL actual bytes for this exact purpose; return trusted current facts.
    /// Complete credential/sensitivity checks and scope/revocation are hard constraints.
    fn review(&self, _call: &SearchCall, _value: &Json, _purpose: &str) -> Result<HostFacts> {
        Err("search_review_unavailable".into())
    }
    /// Persist a held budget reservation plus replay tombstone bound to exact call.
    fn reserve(&self, _call: &SearchCall, _handle: &CredentialHandle) -> Result<String> {
        Err("search_budget_unavailable".into())
    }
    fn release_held(&self, _reservation: &str) -> Result<()> {
        Err("search_release_unavailable".into())
    }
    /// Under the owner's final admission guard, recheck call/config/policy/handle
    /// generation/credential scan/quota, persist one-shot attempt, then exchange.
    /// TLS certificate verification is mandatory; no redirects, proxy fallback,
    /// service/key substitution or automatic retry. Inject Bearer only here.
    /// Consumed/running/unknown request identities MUST NOT send again, even after
    /// restart. Persisted owner attempts, not this crate's phase, prevent replay.
    fn exchange_once(
        &self,
        _reservation: &str,
        _call: &SearchCall,
        _handle: &CredentialHandle,
    ) -> Exchange {
        Exchange::NotSent
    }
    /// Atomically retain the attempt/tombstone. Unknown retains its conservative
    /// hold; only authoritative reconciliation can release it. Never refund a
    /// completed nonempty request. Empty/failed release spend but retain identity.
    fn settle(&self, _reservation: &str, _call: &SearchCall, _outcome: Settlement) -> Result<()> {
        Err("search_settlement_unavailable".into())
    }
}
pub trait SearchProvider {
    fn id(&self) -> &str;
    fn endpoint(&self) -> &str;
    fn price(&self, currency: &str) -> Result<Money>;
    fn encode(&self, query: &str, count: u64) -> Result<Json>;
    /// Return normalized source records, not instructions or grants.
    fn decode(&self, body: &[u8], requested_count: u64) -> Result<Vec<Json>>;
}
pub(crate) fn identity(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 256
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_.-:/".contains(&b))
}
pub(crate) fn admitted(f: HostFacts) -> Result<()> {
    match authorize(
        f.mode,
        f.high,
        f.confirmed,
        f.hard_ok && !f.revoked && f.scope_ok && f.classification_ok,
    ) {
        Decision::Permit => Ok(()),
        Decision::ConfirmationRequired => Err("search_confirmation_required".into()),
        Decision::Denied => Err("search_authority_denied".into()),
    }
}
pub(crate) fn validate(config: &SearchConfig, provider: &dyn SearchProvider) -> Result<()> {
    if !config.enabled {
        return Err("search_disabled".into());
    }
    if config.provider != provider.id()
        || config.endpoint != provider.endpoint()
        || !config.endpoint.starts_with("https://")
        || config.credential_generation == 0
        || config.max_response_bytes == 0
        || config.max_response_bytes > 32768
        || [
            &config.id,
            &config.provider,
            &config.revision,
            &config.policy_revision,
            &config.endpoint_identity,
            &config.credential_ref,
        ]
        .iter()
        .any(|v| !identity(v))
        || config.price != provider.price(&config.price.currency)?
    {
        return Err("search_config_invalid".into());
    }
    Ok(())
}
pub fn availability(host: &dyn SearchHost, provider: &dyn SearchProvider) -> Result<()> {
    let c = host
        .current()
        .map_err(|_| "search_config_unavailable")?
        .ok_or("search_unconfigured")?;
    validate(&c, provider)?;
    if !host.transport_ready(&c) {
        return Err("search_transport_unavailable".into());
    }
    let h = host
        .handle(&c)
        .map_err(|_| "search_credential_unavailable")?;
    check_handle(&c, &h)?;
    if host
        .current()
        .map_err(|_| "search_config_unavailable")?
        .as_ref()
        != Some(&c)
    {
        return Err("search_config_changed".into());
    }
    Ok(())
}
fn check_handle(c: &SearchConfig, h: &CredentialHandle) -> Result<()> {
    if h.reference() != c.credential_ref
        || h.generation() != Some(c.credential_generation)
        || !identity(h.identity())
    {
        Err("search_credential_changed".into())
    } else {
        Ok(())
    }
}
pub(crate) struct Held {
    host: Rc<dyn SearchHost>,
    pub id: String,
    consumed: bool,
}
impl Held {
    fn new(host: Rc<dyn SearchHost>, id: String) -> Self {
        Self {
            host,
            id,
            consumed: false,
        }
    }
}
impl Drop for Held {
    fn drop(&mut self) {
        if !self.consumed {
            let _ = self.host.release_held(&self.id);
        }
    }
}
