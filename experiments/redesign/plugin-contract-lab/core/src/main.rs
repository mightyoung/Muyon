//! Private line protocol. EOF drops every transient ticket. Frame reads are
//! bounded before allocation; no handler, storage or network exists here.
use std::io::{self, BufRead, Read, Write};
use muyon_plugin_contract_lab::{Catalog, parse, object, string, Json};
fn main() {
    let mut catalog = Catalog::new();
    let stdin = io::stdin();
    let mut input = stdin.lock();
    let mut stdout = io::stdout().lock();
    loop {
        let mut line=Vec::new();
        let count=(&mut input).take(65538).read_until(b'\n',&mut line);
        let Ok(n)=count else { break };
        if n==0 {break;}
        let complete=line.last()==Some(&b'\n');
        if complete {line.pop();}
        let mut terminal=false;
        let reply = if line.len()>65536 || !complete {
            object([("ok",Json::Bool(false)),("code",string("frame_limit_or_eof"))])
        } else {match parse(&line) {
            Ok(request) => catalog.handle(request),
            Err(_) => {terminal=true;object([("ok", Json::Bool(false)), ("code", string("invalid_json"))])},
        }};
        if writeln!(stdout, "{}", reply.encode()).and_then(|_| stdout.flush()).is_err() { break; }
        if terminal || !complete || line.len()>65536 || reply.object().ok().and_then(|m|m.get("code")).and_then(|v|v.string().ok()).is_some_and(|code|matches!(code,"protocol_envelope"|"protocol_version"|"unsupported_command"|"unexpected_or_missing_field")) {break;}
    }
}
