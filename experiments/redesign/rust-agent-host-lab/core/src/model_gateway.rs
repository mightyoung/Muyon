//! Synthetic endpoints receive exactly the bytes admitted and durably journaled.
//! The optional HTTP adapter connects only to numeric loopback, without credentials.
use crate::{string, Json, SharedSession};
use muyon_core_agent_lab::{
    http_transport::{LoopbackHttpConfig, LoopbackHttpTransport},
    model::{ModelEvent, ModelRequest, NativeMessage, Provider, ProviderControl},
    wire_provider::encode_registered_request,
    wire_sse::{Decoder, Usage},
    Result,
};
pub trait OfflineEndpoint {
    fn exchange(&mut self, payload: &[u8], control: &mut dyn ProviderControl) -> Result<Vec<u8>>;
}
/// Local synthetic HTTP adapter. Admission, journaling and budgets remain owned by
/// ModelGateway and Agent; this adapter never retries or registers tools.
pub struct LoopbackEndpoint {
    session: SharedSession,
    transport: LoopbackHttpTransport,
}
impl LoopbackEndpoint {
    pub fn new(session: SharedSession, config: LoopbackHttpConfig) -> Result<Self> {
        Ok(Self { session, transport: LoopbackHttpTransport::new(config)? })
    }
}
impl OfflineEndpoint for LoopbackEndpoint {
    fn exchange(&mut self, payload: &[u8], control: &mut dyn ProviderControl) -> Result<Vec<u8>> {
        let session = &self.session;
        self.transport.exchange(payload, control, &mut |bytes| {
            session.borrow().review_payload(bytes)
        })
    }
}
pub struct ModelGateway {
    pub session: SharedSession,
    pub endpoint: Box<dyn OfflineEndpoint>,
    usage: Usage,
}
impl ModelGateway {
    pub fn new(session: SharedSession, endpoint: Box<dyn OfflineEndpoint>) -> Self {
        Self {
            session,
            endpoint,
            usage: Usage::default(),
        }
    }
}
impl Provider for ModelGateway {
    fn respond(&mut self, _request: &ModelRequest, _position: usize) -> Result<ModelEvent> {
        Err("controlled_gateway_required".into())
    }
    fn respond_controlled(
        &mut self,
        request: &ModelRequest,
        _position: usize,
        _history: &[NativeMessage],
        control: &mut dyn ProviderControl,
    ) -> Result<ModelEvent> {
        self.session.borrow().poll_service_control()?;
        control.poll()?;
        let (history, definitions) = {
            let s = self.session.borrow();
            (s.model_history(), s.definitions())
        };
        let bytes = encode_registered_request(request, &history, &definitions, "offline-fixture")?;
        {
            let s = self.session.borrow();
            s.review_payload(&bytes)?;
            s.store.ledger("begin", &bytes)
                .map_err(|_| "model_ledger_failed")?;
            s.review_payload(&bytes)?;
        }
        control.poll()?;
        // The endpoint is in-process synthetic Rust, and exchange performs no await
        // between this final synchronous current-authority check and byte admission.
        {
            let mut s = self.session.borrow_mut();
            s.review_payload(&bytes)?;
            s.model_sends += 1;
        }
        let response = match self.endpoint.exchange(&bytes, control) {
            Ok(v) if v.len() <= 65536 => v,
            result => {
                // A failed durable ledger takes priority over a cooperative stop.
                self.session.borrow().store.ledger("failed", &bytes)
                    .map_err(|_| "model_ledger_failed")?;
                return Err(match result {
                    Err(reason) if matches!(reason.as_str(),
                        "native_cancelled" | "native_deadline" | "wire_cancelled"
                        | "wire_total_limit" | "wire_journal") => {
                        reason
                    }
                    _ => "model_transport_failed".into(),
                });
            }
        };
        self.session.borrow().store.ledger("sent", &bytes)
            .map_err(|_| "model_ledger_failed")?;
        let advertised: Vec<_> = definitions
            .iter()
            .filter(|d| request.tools.contains(&d.name))
            .cloned()
            .collect();
        let mut decoder = Decoder::with_tools(&advertised)?;
        for byte in response {
            self.session.borrow().poll_service_control()?;
            control.poll()?;
            decoder.feed(byte)?;
        }
        let decoded = decoder.finish()?;
        self.usage = decoded.usage;
        match decoded.event {
            ModelEvent::Answer(text) => {
                let mut s = self.session.borrow_mut();
                let safe = s.review.mask_answer(&text)?;
                s.history.push(crate::object([
                    ("role", string("assistant")),
                    ("content", string(&safe)),
                ]));
                Ok(ModelEvent::Answer(safe))
            }
            ModelEvent::HostTool {
                call_ref,
                name,
                arguments,
            } => {
                self.session.borrow().review.review(
                    &Json::Array(vec![string(&call_ref), string(&name), arguments.clone()]),
                    self.session.borrow().store.facts(),
                    "model_context",
                )?;
                Ok(ModelEvent::HostTool {
                    call_ref,
                    name,
                    arguments,
                })
            }
            _ => Err("native_model_event".into()),
        }
    }
    fn reported_usage(&self) -> (Option<u64>, Option<u64>) {
        (self.usage.prompt, self.usage.completion)
    }
}
