//! Private contract admission transport. Business handlers and receipts stay host-owned.
use crate::{Json, Result};
pub trait ContractTransport {
    fn request(&mut self, request: Json) -> Result<Json>;
    fn close(&mut self);
    fn child_pid(&self) -> Option<u32> {
        None
    }
}
pub struct InProcessCatalog;
impl Default for InProcessCatalog {
    fn default() -> Self {
        Self::new()
    }
}
impl InProcessCatalog {
    pub fn new() -> Self {
        Self
    }
    pub fn request_line(&mut self, _line: &[u8]) -> Result<Json> {
        eprintln!("CONTRACT_TRANSPORT_STUB_REACHED");
        Err("contract_transport_stub".into())
    }
}
impl ContractTransport for InProcessCatalog {
    fn request(&mut self, _request: Json) -> Result<Json> {
        self.request_line(&[])
    }
    fn close(&mut self) {}
}
