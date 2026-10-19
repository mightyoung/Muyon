//! Settings-aware registered ordinary-Send composition; synthetic installation only.
//! Real SearchHost/owner/TLS remains an independently coordinated integration port.
use crate::{deepseek::DeepSeek, runtime, *};
use muyon_core_agent_lab::{
    agent::{Agent, Limits, State},
    model::{ModelEvent, ModelRequest, Provider, Role},
    policy::{HostFacts, Mode},
    store,
};
use muyon_rust_agent_host_lab::{
    ordinary_chat::check_text,
    service_provider::CredentialHandle,
    service_runtime::RunControl,
    service_tools::{RegisteredChatResult, RegisteredChatRoute},
    *,
};
use std::{cell::RefCell, path::Path, rc::Rc, sync::Arc};
pub trait ToolSettingsSource: Send + Sync {
    fn snapshot(&self) -> Result<Json>;
}
pub struct ConfiguredToolRoute {
    pub settings: Arc<dyn ToolSettingsSource>,
    pub synthetic: bool,
}
fn get<'a>(j: &'a Json, k: &str) -> Result<&'a Json> {
    j.object()?
        .get(k)
        .ok_or_else(|| "search_config_corrupt".into())
}
fn settings(source: &dyn ToolSettingsSource) -> Result<Json> {
    let j = source.snapshot().map_err(|_| "search_config_corrupt")?;
    let m = j.object().map_err(|_| "search_config_corrupt")?;
    if m.len() != 5
        || ["version", "enabled", "provider", "connection", "revision"]
            .iter()
            .any(|k| !m.contains_key(*k))
        || j.encode().len() > 1024
        || get(&j, "version")?.integer() != Ok(1)
        || !matches!(get(&j, "enabled")?, Json::Bool(_))
        || get(&j, "provider")? != &string("deepseek-search")
        || !["", "search-connection"].contains(&get(&j, "connection")?.string()?)
        || get(&j, "revision")?.integer()? == 0
    {
        return Err("search_config_corrupt".into());
    }
    Ok(j)
}
fn fixture_config(s: &Json) -> Result<SearchConfig> {
    Ok(SearchConfig {
        enabled: true,
        id: "search-connection".into(),
        provider: "deepseek-search".into(),
        revision: format!("c{}", get(s, "revision")?.integer()?),
        policy_revision: "synthetic-search-policy1".into(),
        endpoint: DeepSeek.endpoint().into(),
        endpoint_identity: "deepseek-search-official".into(),
        credential_ref: "synthetic-search-handle-ref".into(),
        credential_generation: 1,
        price: DeepSeek.price("USD")?,
        max_response_bytes: 32768,
    })
}
fn same(source: &dyn ToolSettingsSource, route: &Json) -> Result<()> {
    if settings(source)? != *get(route, "settings")? {
        Err("search_config_changed".into())
    } else {
        Ok(())
    }
}
struct FixtureHost {
    source: Arc<dyn ToolSettingsSource>,
    snapshot: Json,
    dir: std::path::PathBuf,
    config: SearchConfig,
    phase: RefCell<String>,
}
impl FixtureHost {
    fn write(&self, call: &SearchCall, status: &str) -> Result<()> {
        store::atomic(
            &self.dir,
            "search-outbound.db",
            &object([
                ("version", string("synthetic-search-send-1")),
                ("task", string(&call.invocation.task)),
                ("attempt", string(&call.invocation.attempt)),
                ("call", string(&call.invocation.call_ref)),
                ("config", self.snapshot.clone()),
                (
                    "payload",
                    string(
                        String::from_utf8(call.payload.clone())
                            .map_err(|_| "search_payload_invalid")?,
                    ),
                ),
                ("status", string(status)),
                ("currency", string(&call.max_cost.currency)),
                ("max_micros", Json::Number(call.max_cost.micros.to_string())),
                ("synthetic", Json::Bool(true)),
                ("credential_ref", string(&self.config.credential_ref)),
                ("credential_generation", Json::Number("1".into())),
                ("credential_identity", string("synthetic-search-capability")),
            ])
            .encode(),
        )
    }
}
impl SearchHost for FixtureHost {
    fn current(&self) -> Result<Option<SearchConfig>> {
        if settings(self.source.as_ref())? != self.snapshot {
            return Err("search_config_changed".into());
        }
        Ok(Some(self.config.clone()))
    }
    fn transport_ready(&self, _: &SearchConfig) -> bool {
        true
    }
    fn handle(&self, c: &SearchConfig) -> Result<CredentialHandle> {
        CredentialHandle::with_generation(
            &c.id,
            &c.credential_ref,
            "synthetic-search-capability",
            1,
        )
    }
    fn review(&self, _: &SearchCall, value: &Json, _: &str) -> Result<HostFacts> {
        scan(value)?;
        self.current()?;
        Ok(HostFacts {
            mode: Mode::FullAllow,
            high: true,
            tainted: true,
            new_destination: true,
            ..HostFacts::default()
        })
    }
    fn reserve(&self, call: &SearchCall, _: &CredentialHandle) -> Result<String> {
        if !self.phase.borrow().is_empty() || self.dir.join("search-outbound.db").exists() {
            return Err("search_duplicate_call".into());
        }
        self.write(call, "held")?;
        *self.phase.borrow_mut() = "held".into();
        Ok("synthetic-search-reservation".into())
    }
    fn release_held(&self, _: &str) -> Result<()> {
        if self.phase.borrow().as_str() == "held" {
            *self.phase.borrow_mut() = "released".into();
        }
        Ok(())
    }
    fn exchange_once(&self, _: &str, call: &SearchCall, h: &CredentialHandle) -> Exchange {
        if self.current().ok().flatten().as_ref() != Some(&call.config)
            || h.generation() != Some(1)
            || self.phase.borrow().as_str() != "held"
        {
            return Exchange::NotSent;
        }
        if self.write(call, "unknown").is_err() {
            return Exchange::NotSent;
        }
        *self.phase.borrow_mut() = "unknown".into();
        let q = parse(&call.payload)
            .ok()
            .and_then(|j| {
                get(&j, "query")
                    .ok()
                    .and_then(|v| v.string().ok())
                    .map(str::to_owned)
            })
            .unwrap_or_default();
        if q == "unknown fixture" {
            return Exchange::Unknown;
        }
        let (status, body) = if q == "empty fixture" {
            (200, b"{\"results\":[]}".to_vec())
        } else if q == "error fixture" {
            (401, b"{}".to_vec())
        } else {
            (200, include_bytes!("../../fixtures/nonempty.json").to_vec())
        };
        Exchange::Http {
            status,
            content_type: "application/json".into(),
            body,
        }
    }
    fn settle(&self, _: &str, call: &SearchCall, outcome: Settlement) -> Result<()> {
        let name = match outcome {
            Settlement::Nonempty => "nonempty",
            Settlement::Empty => "empty",
            Settlement::Failed => "failed",
            Settlement::Unknown => "unknown",
        };
        self.write(call, name)?;
        *self.phase.borrow_mut() = name.into();
        Ok(())
    }
}
fn scan(j: &Json) -> Result<()> {
    match j {
        Json::String(s) if !s.is_empty() => check_text(s),
        Json::Array(a) => {
            for v in a {
                scan(v)?
            }
            Ok(())
        }
        Json::Object(m) => {
            for v in m.values() {
                scan(v)?
            }
            Ok(())
        }
        _ => Ok(()),
    }
}
struct Authority {
    config: SearchConfig,
    settings: Arc<dyn ToolSettingsSource>,
    snapshot: Json,
}
impl AuthoritySource for Authority {
    fn snapshot(&self) -> Result<AuthoritySnapshot> {
        if settings(self.settings.as_ref())? != self.snapshot {
            return Err("search_config_changed".into());
        }
        Ok(AuthoritySnapshot {
            read: object([
                ("allowed", Json::Bool(true)),
                ("available", Json::Bool(true)),
                ("scope_allowed", Json::Bool(true)),
                ("bindings", Json::Array(vec![string("host-web-search")])),
                ("revision", string(&self.config.revision)),
                ("binding_revision", string(&self.config.revision)),
                ("source_revision", string(&self.config.revision)),
                ("rule_revision", string("synthetic-search-policy1")),
                ("scope", string("registered-chat")),
                ("refs", Json::Array(vec![connection(&self.config)])),
            ]),
            model_allowed: true,
            profile: "offline-fixture".into(),
        })
    }
}
fn connection(c: &SearchConfig) -> Json {
    object([
        ("module_id", string("web_search")),
        ("type", string("connection")),
        ("key", string(&c.id)),
        ("revision", string(&c.revision)),
        ("schema_version", Json::Number("1".into())),
    ])
}
struct Review;
impl PurposeReview for Review {
    fn review(&self, j: &Json, _: &Json, _: &str) -> Result<()> {
        scan(j)
    }
    fn mask_answer(&self, s: &str) -> Result<String> {
        check_text(s)?;
        Ok(s.into())
    }
}
struct Model {
    query: String,
}
impl Provider for Model {
    fn respond(&mut self, r: &ModelRequest, _: usize) -> Result<ModelEvent> {
        if r.turn == 1 {
            let name = r.tools.first().ok_or("search_tool_not_registered")?.clone();
            Ok(ModelEvent::HostTool {
                call_ref: "search-call1".into(),
                name,
                arguments: object([
                    ("query", string(&self.query)),
                    ("count", Json::Number("10".into())),
                ]),
            })
        } else {
            let value = r
                .messages
                .iter()
                .find(|m| m.role == Role::Tool)
                .ok_or("search_result_missing")?;
            let p = parse(value.text.as_bytes())?;
            let empty = get(&p, "sources")?.array()?.is_empty();
            Ok(ModelEvent::Answer(
                if empty {
                    "没有找到匹配结果（离线合成）"
                } else {
                    "离线搜索已完成；来源见下方"
                }
                .into(),
            ))
        }
    }
}
impl RegisteredChatRoute for ConfiguredToolRoute {
    fn prepare(&self, _: &str, text: &str) -> Result<Option<Json>> {
        let s = settings(self.settings.as_ref())?;
        if get(&s, "enabled")? == &Json::Bool(false) {
            return Ok(None);
        }
        let status = if get(&s, "connection")? == &string("") {
            "search_unconfigured"
        } else if !self.synthetic {
            "search_transport_unavailable"
        } else {
            "ready"
        };
        let arguments = if request(text, 10).is_ok() {
            object([
                ("query", string(text)),
                ("count", Json::Number("10".into())),
            ])
        } else {
            Json::Null
        };
        let status = if status == "ready" && arguments == Json::Null {
            "search_request_invalid"
        } else {
            status
        };
        let c = fixture_config(&s)?;
        Ok(Some(object([
            ("tool", string("web_search.search")),
            ("settings", s),
            ("scope", string("registered-chat")),
            ("scope_refs", Json::Array(vec![connection(&c)])),
            ("arguments", arguments),
            ("status", string(status)),
        ])))
    }
    fn execute(
        &self,
        dir: &Path,
        input: &Json,
        route: &Json,
        control: Arc<RunControl>,
        admitted: &mut dyn FnMut(&State) -> Result<()>,
    ) -> Result<RegisteredChatResult> {
        if get(route, "status")?.string()? != "ready" {
            return Err(get(route, "status")?.string()?.into());
        }
        same(self.settings.as_ref(), route)?;
        if !self.synthetic {
            return Err("search_transport_unavailable".into());
        }
        let s = get(route, "settings")?.clone();
        let c = fixture_config(&s)?;
        let text = get(input, "text")?.string()?;
        check_text(text)?;
        request(text, 10)?;
        let session = NativeSession::service_in_process(
            dir,
            Rc::new(Authority {
                config: c.clone(),
                settings: self.settings.clone(),
                snapshot: s.clone(),
            }),
            Rc::new(Review),
            text,
            control,
        )?;
        let host = Rc::new(FixtureHost {
            source: self.settings.clone(),
            snapshot: s,
            dir: dir.into(),
            config: c,
            phase: RefCell::new(String::new()),
        });
        let mut runtime = runtime::install(session.clone(), host, Rc::new(DeepSeek))?;
        let state = State::runtime(
            text.into(),
            "registered-chat".into(),
            Limits {
                steps: 3,
                calls: 3,
                context: 32768,
                output: 32768,
                total: 131072,
            },
        )?;
        admitted(&state)?;
        let mut agent = Agent {
            dir: dir.into(),
            state,
        };
        runtime.run(&mut agent, &mut Model { query: text.into() })?;
        let completed = agent.state.status == "completed";
        let row = session.borrow().store.receipts().first().cloned();
        Ok(RegisteredChatResult {
            state: agent.state.status,
            reason: if completed {
                "none".into()
            } else {
                agent.state.reason
            },
            answer: agent.state.answer,
            projection: if completed {
                row.as_ref().and_then(|r| get(r, "raw").ok()).cloned()
            } else {
                None
            },
            receipt: if completed {
                row.as_ref().and_then(|r| get(r, "identity").ok()).cloned()
            } else {
                None
            },
        })
    }
    fn restore(&self, dir: &Path, input: &Json, route: &Json, result: &Json) -> Result<()> {
        check_text(get(input, "text")?.string()?)?;
        if get(result, "route")? != route {
            return Err("search_route_identity".into());
        }
        let completed = get(result, "state")? == &string("completed");
        let path = dir.join("search-outbound.db");
        if !completed && !path.exists() {
            return Ok(());
        }
        let meta = std::fs::symlink_metadata(&path).map_err(|_| "search_outbound_missing")?;
        if !meta.is_file() || meta.file_type().is_symlink() || meta.len() > 8192 {
            return Err("search_outbound_invalid".into());
        }
        use std::io::Read;
        let mut bytes = Vec::new();
        std::fs::File::open(path)
            .map_err(|_| "search_outbound_missing")?
            .take(8193)
            .read_to_end(&mut bytes)
            .map_err(|_| "search_outbound_missing")?;
        if bytes.len() > 8192 {
            return Err("search_outbound_invalid".into());
        }
        let ledger = parse(&bytes)?;
        let m = ledger.object()?;
        let keys = [
            "version",
            "task",
            "attempt",
            "call",
            "config",
            "payload",
            "status",
            "currency",
            "max_micros",
            "synthetic",
            "credential_ref",
            "credential_generation",
            "credential_identity",
        ];
        if m.len() != keys.len() || keys.iter().any(|k| !m.contains_key(*k)) {
            return Err("search_outbound_invalid".into());
        }
        let config = fixture_config(get(route, "settings")?)?;
        if get(&ledger, "version")? != &string("synthetic-search-send-1")
            || get(&ledger, "config")? != get(route, "settings")?
            || get(&ledger, "task")? != get(result, "task")?
            || get(&ledger, "attempt")? != get(result, "attempt")?
            || get(&ledger, "currency")? != &string(&config.price.currency)
            || get(&ledger, "max_micros")?.integer()? != config.price.micros
            || get(&ledger, "synthetic")? != &Json::Bool(true)
            || get(&ledger, "credential_ref")? != &string(&config.credential_ref)
            || get(&ledger, "credential_generation")?.integer()? != config.credential_generation
            || get(&ledger, "credential_identity")? != &string("synthetic-search-capability")
        {
            return Err("search_outbound_identity".into());
        }
        let expected = request(get(input, "text")?.string()?, 10)?;
        if get(&ledger, "payload")? != &string(expected.encode())
            || get(route, "arguments")?
                != &object([
                    ("query", get(input, "text")?.clone()),
                    ("count", Json::Number("10".into())),
                ])
        {
            return Err("search_query_identity".into());
        }
        let (rows, _) = muyon_rust_agent_host_lab::store::NativeStore::read_service_evidence(dir)?;
        if rows.len() != 1 {
            return Err("search_receipt_count".into());
        }
        let binding = get(&rows[0], "binding")?;
        if get(binding, "args")?
            != &object([
                ("query", get(input, "text")?.clone()),
                ("count", Json::Number("10".into())),
            ])
        {
            return Err("search_query_identity".into());
        }
        if completed {
            let p = get(result, "projection")?;
            let request = get(p, "request")?;
            if get(request, "task")? != get(&ledger, "task")?
                || get(request, "attempt")? != get(&ledger, "attempt")?
                || get(request, "call")? != get(&ledger, "call")?
            {
                return Err("search_call_identity".into());
            }
            let empty = get(p, "sources")?.array()?.is_empty();
            if get(&ledger, "status")? != &string(if empty { "empty" } else { "nonempty" })
                || get(p, "cost_micros")?.integer()? != if empty { 0 } else { config.price.micros }
                || get(p, "currency")? != &string(&config.price.currency)
            {
                return Err("search_cost_identity".into());
            }
        } else if !["failed", "unknown"].contains(&get(&ledger, "status")?.string()?) {
            return Err("search_failure_identity".into());
        }
        Ok(())
    }
    fn disclose(&self, dir: &Path, input: &Json, route: &Json, result: &Json) -> Result<()> {
        self.restore(dir, input, route, result)?;
        same(self.settings.as_ref(), route)?;
        if !self.synthetic {
            return Err("search_transport_unavailable".into());
        }
        scan(get(result, "projection")?)?;
        check_text(get(result, "answer")?.string()?)?;
        let c = fixture_config(get(route, "settings")?)?;
        let p = get(result, "projection")?;
        if get(p, "provider")? != &string(DeepSeek.id()) || get(p, "connection")? != &connection(&c)
        {
            return Err("search_source_identity".into());
        }
        Ok(())
    }
}
