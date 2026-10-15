//! Compileable refusing wire shell for the first behavioral RED.
use std::io::{self, BufRead, Write};
use muyon_plugin_contract_lab::{Catalog, parse, object, string, Json};
fn main() {
    let mut catalog = Catalog::new();
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let reply = match parse(line.as_bytes()) {
            Ok(request) => catalog.handle(request),
            Err(_) => object([("ok", Json::Bool(false)), ("code", string("invalid_json"))]),
        };
        if writeln!(stdout, "{}", reply.encode()).and_then(|_| stdout.flush()).is_err() { break; }
    }
}
