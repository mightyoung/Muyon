//! RED-stage API shell. This crate does not yet publish or authorize anything.
pub use muyon_core_agent_lab::wire_json::{object, parse, string, Json};

#[derive(Default)]
pub struct Catalog;
impl Catalog {
    pub fn new() -> Self { Self }
    pub fn handle(&mut self, _request: Json) -> Json {
        object([("ok", Json::Bool(false)), ("code", string("unsupported"))])
    }
}
