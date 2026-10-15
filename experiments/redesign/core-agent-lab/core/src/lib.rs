//! Offline Linux fixture kernel. No production authority, wire, HTTP or database.
pub mod model;
pub mod policy;
pub mod store;
pub mod agent;
pub use policy::{authorize, Decision, Mode};
pub type Result<T> = std::result::Result<T, String>;
pub fn hex(s: &str) -> String { s.as_bytes().iter().map(|b| format!("{b:02x}")).collect() }
pub fn unhex(s: &str) -> Result<String> {
    if s.len() > 2_097_152 || s.len() % 2 != 0 || !s.bytes().all(|b| b.is_ascii_hexdigit()) { return Err("invalid_hex".into()); }
    let bytes: Vec<u8> = s.as_bytes().chunks_exact(2).map(|p| {
        let digit = |c: u8| if c.is_ascii_digit() { c-b'0' } else { c.to_ascii_lowercase()-b'a'+10 };
        digit(p[0])*16+digit(p[1])
    }).collect();
    String::from_utf8(bytes).map_err(|_| "invalid_utf8".into())
}
pub fn identifier(s: &str) -> bool { !s.is_empty() && s.len() <= 64 && s.bytes().all(|c| c.is_ascii_alphanumeric() || b"_.-".contains(&c)) }
pub mod wire_sse;
pub mod wire_provider;
pub mod wire_json;
pub mod host_session;

pub mod agent_ports;
