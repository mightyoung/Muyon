//! Private bounded admission transport; business handlers and receipts stay host-owned.
use crate::{Json, Result};
use muyon_plugin_contract_lab::{object, parse, string, Catalog};
const MAX_FRAME: usize = 65536;
pub trait ContractTransport {
    fn request(&mut self, request: Json) -> Result<Json>;
    fn close(&mut self);
    fn child_pid(&self) -> Option<u32> {
        None
    }
}
pub struct InProcessCatalog {
    catalog: Option<Catalog>,
}
impl Default for InProcessCatalog {
    fn default() -> Self {
        Self::new()
    }
}
impl InProcessCatalog {
    pub fn new() -> Self {
        Self {
            catalog: Some(Catalog::new()),
        }
    }
    /// One complete JSON-line frame. This is not an arbitrary plugin code runner.
    pub fn request_line(&mut self, line: &[u8]) -> Result<Json> {
        if self.catalog.is_none() {
            return Err("plugin_closed".into());
        }
        let complete = line.last() == Some(&b'\n');
        let body = if complete {
            &line[..line.len() - 1]
        } else {
            line
        };
        let (reply, fatal) = if body.len() > MAX_FRAME || !complete {
            (rejected("frame_limit_or_eof"), true)
        } else if body.contains(&b'\n') {
            // Exactly one complete frame, never a multiline JSON document/stream.
            // CR before the final LF is valid JSON whitespace (CRLF sibling).
            (rejected("invalid_json"), true)
        } else {
            match parse(body) {
                Err(_) => (rejected("invalid_json"), true),
                Ok(request) => {
                    let reply = self
                        .catalog
                        .as_mut()
                        .ok_or("plugin_closed")?
                        .handle(request);
                    let fatal = reply
                        .object()
                        .ok()
                        .and_then(|m| m.get("code"))
                        .and_then(|j| j.string().ok())
                        .is_some_and(|code| {
                            matches!(
                                code,
                                "protocol_envelope"
                                    | "protocol_version"
                                    | "unsupported_command"
                                    | "unexpected_or_missing_field"
                            )
                        });
                    (reply, fatal)
                }
            }
        };
        // Even trusted in-process replies cross the exact wire parser boundary.
        let encoded = reply.encode();
        let decoded = match parse(encoded.as_bytes()) {
            Ok(value) => value,
            Err(_) => {
                self.close();
                return Err("plugin_invalid_json".into());
            }
        };
        if fatal {
            self.close()
        }
        Ok(decoded)
    }
}
fn rejected(code: &str) -> Json {
    object([("ok", Json::Bool(false)), ("code", string(code))])
}
impl ContractTransport for InProcessCatalog {
    fn request(&mut self, request: Json) -> Result<Json> {
        if self.catalog.is_none() {
            return Err("plugin_closed".into());
        }
        if request.encoded_len()? > MAX_FRAME {
            self.close();
            return Err("plugin_frame_limit".into());
        }
        let mut line = request.encode().into_bytes();
        line.push(b'\n');
        self.request_line(&line)
    }
    fn close(&mut self) {
        self.catalog.take();
    }
}
