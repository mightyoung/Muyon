use crate::*;
use muyon_core_agent_lab::{
    agent::{Agent, Hooks, State},
    agent_ports::AgentPorts,
    model::Provider,
};
use muyon_rust_agent_host_lab::{Enrollment, RawRead, ReadHandler, RuntimePorts, SharedSession};
use std::{cell::RefCell, collections::BTreeSet};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Idle,
    Sending,
    ResultPrepared,
    Recorded,
    Unknown,
}
struct Flight {
    invocation: Option<Invocation>,
    seen: BTreeSet<(String, String, String)>,
    phase: Phase,
    reason: String,
    projections: Vec<(SearchCall, Json, String)>,
}
impl Flight {
    fn new() -> Self {
        Self {
            invocation: None,
            seen: BTreeSet::new(),
            phase: Phase::Idle,
            reason: String::new(),
            projections: Vec::new(),
        }
    }
    fn uncertain(&self) -> bool {
        matches!(
            self.phase,
            Phase::Sending | Phase::ResultPrepared | Phase::Unknown
        )
    }
}
pub struct SearchRuntime {
    inner: RuntimePorts,
    flight: Rc<RefCell<Flight>>,
    tool: String,
    host: Rc<dyn SearchHost>,
}
struct Handler {
    host: Rc<dyn SearchHost>,
    provider: Rc<dyn SearchProvider>,
    connection: Json,
    flight: Rc<RefCell<Flight>>,
}
fn get<'a>(j: &'a Json, k: &str) -> Result<&'a Json> {
    j.object()?
        .get(k)
        .ok_or_else(|| "search_request_invalid".into())
}
fn current(h: &dyn SearchHost, c: &SearchConfig) -> Result<()> {
    if h.current()
        .map_err(|_| "search_config_unavailable")?
        .as_ref()
        != Some(c)
    {
        Err("search_config_changed".into())
    } else {
        Ok(())
    }
}
impl Handler {
    fn preflight(&self, args: &Json) -> Result<(SearchCall, Json)> {
        let invocation = self
            .flight
            .borrow()
            .invocation
            .clone()
            .ok_or("search_invocation_unavailable")?;
        let config = self
            .host
            .current()
            .map_err(|_| "search_config_unavailable")?
            .ok_or("search_unconfigured")?;
        validate(&config, self.provider.as_ref())?;
        if !self.host.transport_ready(&config) {
            return Err("search_transport_unavailable".into());
        }
        if get(&self.connection, "key")?.string()? != config.id
            || get(&self.connection, "revision")?.string()? != config.revision
        {
            return Err("search_config_changed".into());
        }
        let count = get(args, "count")?
            .integer()
            .map_err(|_| "search_request_invalid")?;
        let payload = self.provider.encode(get(args, "query")?.string()?, count)?;
        let call = SearchCall {
            config: config.clone(),
            invocation,
            connection: self.connection.clone(),
            payload: payload.encode().into_bytes(),
            max_cost: config.price.clone(),
        };
        admitted(
            self.host
                .review(&call, &payload, "search_query")
                .map_err(|_| "search_content_denied")?,
        )?;
        current(self.host.as_ref(), &config)?;
        Ok((call, payload))
    }
    fn execute(&self, args: &Json) -> Result<RawRead> {
        let (call, payload) = self.preflight(args)?;
        let config = call.config.clone();
        let count = get(args, "count")?.integer()?;
        let handle = self
            .host
            .handle(&config)
            .map_err(|_| "search_credential_unavailable")?;
        check_handle(&config, &handle)?;
        admitted(
            self.host
                .review(&call, &payload, "search_query")
                .map_err(|_| "search_content_denied")?,
        )?;
        current(self.host.as_ref(), &config)?;
        let id = self
            .host
            .reserve(&call, &handle)
            .map_err(|_| "search_budget_unavailable")?;
        let mut held = Held::new(self.host.clone(), id);
        if !identity(&held.id) {
            return Err("search_budget_unavailable".into());
        }
        current(self.host.as_ref(), &config)?;
        let fresh = self
            .host
            .handle(&config)
            .map_err(|_| "search_credential_unavailable")?;
        if fresh != handle {
            return Err("search_credential_changed".into());
        }
        admitted(
            self.host
                .review(&call, &payload, "search_query")
                .map_err(|_| "search_content_denied")?,
        )?;
        current(self.host.as_ref(), &config)?;
        // Before the owner handoff: no automatic release after an uncertain
        // commit/transport return. Owner atomically decides whether any send starts.
        held.consumed = true;
        self.flight.borrow_mut().phase = Phase::Sending;
        let response = self.host.exchange_once(&held.id, &call, &handle);
        let (status, mime, body) = match response {
            Exchange::NotSent => {
                self.host
                    .settle(&held.id, &call, Settlement::Failed)
                    .map_err(|_| "search_outcome_unknown")?;
                self.flight.borrow_mut().phase = Phase::Idle;
                return Err("search_not_sent".into());
            }
            Exchange::Unknown => {
                let _ = self.host.settle(&held.id, &call, Settlement::Unknown);
                return Err("search_outcome_unknown".into());
            }
            Exchange::Http {
                status,
                content_type,
                body,
            } => (status, content_type, body),
        };
        if status != 200 {
            // No provider body is propagated: it can contain credentials/query text.
            let outcome = if matches!(
                status,
                400 | 401 | 402 | 403 | 404 | 408 | 413 | 429 | 500 | 504
            ) {
                Settlement::Failed
            } else {
                Settlement::Unknown
            };
            self.host
                .settle(&held.id, &call, outcome)
                .map_err(|_| "search_outcome_unknown")?;
            if outcome != Settlement::Unknown {
                self.flight.borrow_mut().phase = Phase::Idle;
            }
            return Err(match status {
                401 => "search_authentication_failed",
                402 => "search_balance_insufficient",
                429 => "search_rate_limited",
                300..=399 => "search_redirect_refused",
                400..=499 => "search_request_rejected",
                _ => "search_service_failed",
            }
            .into());
        }
        if body.len() > config.max_response_bytes
            || !mime
                .split(';')
                .next()
                .is_some_and(|s| s.trim().eq_ignore_ascii_case("application/json"))
        {
            let _ = self.host.settle(&held.id, &call, Settlement::Unknown);
            return Err("search_response_invalid".into());
        }
        let rows = match self.provider.decode(&body, count) {
            Ok(r) => r,
            Err(_) => {
                let _ = self.host.settle(&held.id, &call, Settlement::Unknown);
                return Err("search_response_invalid".into());
            }
        };
        let outcome = if rows.is_empty() {
            Settlement::Empty
        } else {
            Settlement::Nonempty
        };
        self.host
            .settle(&held.id, &call, outcome)
            .map_err(|_| "search_outcome_unknown")?;
        let actual = if rows.is_empty() {
            0
        } else {
            call.max_cost.micros
        };
        let value = object([
            ("provider", string(&config.provider)),
            ("connection", self.connection.clone()),
            (
                "request",
                object([
                    ("task", string(&call.invocation.task)),
                    ("attempt", string(&call.invocation.attempt)),
                    ("call", string(&call.invocation.call_ref)),
                ]),
            ),
            ("sources", Json::Array(rows)),
            ("tainted", Json::Bool(true)),
            ("instruction_authority", Json::Bool(false)),
            ("currency", string(&call.max_cost.currency)),
            ("cost_micros", Json::Number(actual.to_string())),
            (
                "billing",
                string(if actual == 0 {
                    "empty_success"
                } else {
                    "nonempty_success"
                }),
            ),
        ]);
        // Catalog's explicit bounded dialect applies before raw receipt persistence.
        // Result schema is a host-normalized projection, not the upstream schema.
        if value.encoded_len()? > 16384 {
            return Err("search_projection_limit".into());
        }
        admitted(
            self.host
                .review(&call, &value, "search_result")
                .map_err(|_| "search_content_denied")?,
        )?;
        current(self.host.as_ref(), &config)?;
        self.flight
            .borrow_mut()
            .projections
            .push((call, value.clone(), handle.identity().into()));
        self.flight.borrow_mut().phase = Phase::ResultPrepared;
        Ok(RawRead {
            raw: value.clone(),
            projection: value,
        })
    }
}
impl ReadHandler for Handler {
    fn admit_read(&self, args: &Json, refs: &[Json]) -> Result<()> {
        if refs != [self.connection.clone()]
            || self.flight.borrow().invocation.is_none()
            || args.object()?.len() != 2
        {
            return Err("search_scope_denied".into());
        }
        request(
            get(args, "query")?.string()?,
            get(args, "count")?.integer()?,
        )?;
        if let Err(e) = self.preflight(args) {
            self.flight.borrow_mut().reason = e.clone();
            return Err(e);
        }
        Ok(())
    }
    fn read(&mut self, args: &Json) -> Result<RawRead> {
        let result = self.execute(args);
        if let Err(ref e) = result {
            self.flight.borrow_mut().reason = e.clone();
        }
        result
    }
}
/// Register a host connection as the capability scope; webpages are dynamic
/// provenance records, never fabricated local ObjectRefs or service citation IDs.
pub fn install(
    session: SharedSession,
    host: Rc<dyn SearchHost>,
    provider: Rc<dyn SearchProvider>,
) -> Result<SearchRuntime> {
    availability(host.as_ref(), provider.as_ref())?;
    let c = host
        .current()
        .map_err(|_| "search_config_unavailable")?
        .ok_or("search_unconfigured")?;
    validate(&c, provider.as_ref())?;
    let connection = object([
        ("module_id", string("web_search")),
        ("type", string("connection")),
        ("key", string(&c.id)),
        ("revision", string(&c.revision)),
        ("schema_version", Json::Number("1".into())),
    ]);
    let flight = Rc::new(RefCell::new(Flight::new()));
    session.borrow_mut().register(Enrollment {
        bundle: bundle(),
        operation: "web_search/search@1".into(),
        tool_id: "web_search.search".into(),
        binding_id: "host-web-search".into(),
        scope_refs: vec![connection.clone()],
        handler: Box::new(Handler {
            host: host.clone(),
            provider,
            connection,
            flight: flight.clone(),
        }),
    })?;
    Ok(SearchRuntime {
        inner: RuntimePorts { session },
        flight,
        tool: "web_search.search".into(),
        host,
    })
}
fn normalize(state: &mut State, flight: &Flight) {
    if flight.uncertain() {
        state.status = "outcome_unknown".into();
        state.reason = "search_outcome_unknown".into();
        state.answer.clear();
    }
}
impl SearchRuntime {
    fn review_current_results(&self) -> Result<()> {
        for (call, value, handle_identity) in &self.flight.borrow().projections {
            current(self.host.as_ref(), &call.config)?;
            let h = self
                .host
                .handle(&call.config)
                .map_err(|_| "search_credential_unavailable")?;
            check_handle(&call.config, &h)?;
            if h.identity() != handle_identity {
                return Err("search_credential_changed".into());
            }
            admitted(
                self.host
                    .review(call, value, "search_result")
                    .map_err(|_| "search_content_denied")?,
            )?;
        }
        Ok(())
    }
    /// Required drive entry: finalizes both direct Agent stop and Result::Err.
    /// On a write failure, state remains unknown in memory; durable owner attempt
    /// is the authority, and Err explicitly reports that local persistence failed.
    pub fn run(&mut self, agent: &mut Agent, provider: &mut dyn Provider) -> Result<()> {
        if self.flight.borrow().uncertain() {
            normalize(&mut agent.state, &self.flight.borrow());
            return self.persist(agent);
        }
        let result = agent.run_with_runtime_ports(provider, self, &Hooks::default());
        if result.is_err() && self.flight.borrow().phase != Phase::Idle {
            self.flight.borrow_mut().phase = Phase::Unknown;
        }
        normalize(&mut agent.state, &self.flight.borrow());
        self.persist(agent)
            .map_err(|_| "search_state_persistence_failed")?;
        result
    }
}
impl AgentPorts for SearchRuntime {
    fn advertised_tools(&self, s: &State) -> Result<Vec<String>> {
        if self.flight.borrow().uncertain() {
            return Err("search_outcome_unknown".into());
        }
        self.review_current_results()?;
        self.inner.advertised_tools(s)
    }
    fn persist(&self, agent: &Agent) -> Result<()> {
        let mut state = agent.state.clone();
        normalize(&mut state, &self.flight.borrow());
        self.inner.persist(&Agent {
            dir: agent.dir.clone(),
            state,
        })
    }
    fn check_control(&mut self) -> Result<()> {
        self.inner.check_control()
    }
    fn dispatch(
        &mut self,
        a: &mut Agent,
        call_ref: String,
        name: String,
        args: Json,
    ) -> Result<()> {
        if name != self.tool {
            return self.inner.dispatch(a, call_ref, name, args);
        }
        {
            let mut f = self.flight.borrow_mut();
            if f.uncertain()
                || f.invocation.is_some()
                || !f.seen.insert((
                    a.state.task.clone(),
                    a.state.attempt.clone(),
                    call_ref.clone(),
                ))
            {
                return Err("search_duplicate_call".into());
            }
            f.phase = Phase::Idle;
            f.reason.clear();
            f.invocation = Some(Invocation {
                task: a.state.task.clone(),
                attempt: a.state.attempt.clone(),
                scope: a.state.scope.clone(),
                turn: a.state.counters.steps,
                call_ref: call_ref.clone(),
            });
        }
        let result = self.inner.dispatch(a, call_ref, name, args);
        let mut f = self.flight.borrow_mut();
        f.invocation = None;
        if result.is_ok() && f.phase == Phase::ResultPrepared {
            f.phase = Phase::Recorded;
        }
        if result.is_err() && f.uncertain() {
            f.phase = Phase::Unknown;
        }
        result
    }
    fn admit_answer(&self, s: &State, answer: &str) -> Result<()> {
        if self.flight.borrow().uncertain() {
            return Err("search_outcome_unknown".into());
        }
        self.review_current_results()?;
        for (call, _, _) in &self.flight.borrow().projections {
            admitted(
                self.host
                    .review(call, &string(answer), "model_answer")
                    .map_err(|_| "search_content_denied")?,
            )?;
        }
        self.inner.admit_answer(s, answer)
    }
    fn failure(&mut self, s: &mut State, reason: &str) {
        self.inner.failure(s, reason);
        let f = self.flight.borrow();
        if f.uncertain() {
            normalize(s, &f)
        } else if !f.reason.is_empty() {
            s.reason = f.reason.clone();
        }
    }
}
fn schema(typ: &str) -> Json {
    object([("type", string(typ))])
}
fn object_schema(properties: Vec<(&str, Json)>, required: &[&str]) -> Json {
    object([
        ("type", string("object")),
        ("properties", object(properties)),
        (
            "required",
            Json::Array(required.iter().map(|s| string(*s)).collect()),
        ),
        ("additionalProperties", Json::Bool(false)),
    ])
}
pub fn bundle() -> Json {
    let reference = object_schema(
        vec![
            ("module_id", schema("string")),
            ("type", schema("string")),
            ("key", schema("string")),
            ("revision", schema("string")),
            ("schema_version", schema("integer")),
        ],
        &["module_id", "type", "key", "revision", "schema_version"],
    );
    let mut typed = reference;
    if let Json::Object(m) = &mut typed {
        m.insert("data_ref".into(), string("web_search/connection@1"));
    }
    let source_fields = [
        "title",
        "url",
        "snippet",
        "summary",
        "content",
        "site_name",
        "site_icon",
        "date",
        "rerank_score",
    ];
    let mut source = source_fields
        .iter()
        .map(|s| (*s, schema("string")))
        .collect::<Vec<_>>();
    source.extend([
        ("authority", schema("integer")),
        ("rank", schema("integer")),
    ]);
    let source = object_schema(
        source,
        &[
            "title",
            "url",
            "snippet",
            "summary",
            "content",
            "rerank_score",
            "authority",
            "rank",
        ],
    );
    let result = object_schema(
        vec![
            ("provider", schema("string")),
            ("connection", typed),
            (
                "request",
                object_schema(
                    vec![
                        ("task", schema("string")),
                        ("attempt", schema("string")),
                        ("call", schema("string")),
                    ],
                    &["task", "attempt", "call"],
                ),
            ),
            (
                "sources",
                object([
                    ("type", string("array")),
                    ("items", source.clone()),
                    ("maxItems", Json::Number("50".into())),
                ]),
            ),
            ("tainted", schema("boolean")),
            ("instruction_authority", schema("boolean")),
            ("currency", schema("string")),
            ("cost_micros", schema("integer")),
            ("billing", schema("string")),
        ],
        &[
            "provider",
            "connection",
            "request",
            "sources",
            "tainted",
            "instruction_authority",
            "currency",
            "cost_micros",
            "billing",
        ],
    );
    object([
        ("module_id", string("web_search")),
        ("protocol_version", Json::Number("1".into())),
        (
            "data",
            Json::Array(vec![
                object([
                    ("name", string("connection")),
                    ("schema_version", Json::Number("1".into())),
                    (
                        "schema",
                        object_schema(vec![("label", schema("string"))], &[]),
                    ),
                ]),
                object([
                    ("name", string("source")),
                    ("schema_version", Json::Number("1".into())),
                    ("schema", source),
                ]),
                object([
                    ("name", string("response")),
                    ("schema_version", Json::Number("1".into())),
                    ("schema", result.clone()),
                ]),
            ]),
        ),
        ("relations", Json::Array(vec![])),
        (
            "operations",
            Json::Array(vec![object([
                ("name", string("search")),
                ("schema_version", Json::Number("1".into())),
                ("effect", string("read")),
                (
                    "input_schema",
                    object_schema(
                        vec![("query", schema("string")), ("count", schema("integer"))],
                        &["query", "count"],
                    ),
                ),
                ("projection_schema", result),
                (
                    "data_refs",
                    Json::Array(vec![
                        string("web_search/connection@1"),
                        string("web_search/source@1"),
                        string("web_search/response@1"),
                    ]),
                ),
                ("binding_id", string("host-web-search")),
            ])]),
        ),
        ("views", Json::Array(vec![])),
    ])
}
