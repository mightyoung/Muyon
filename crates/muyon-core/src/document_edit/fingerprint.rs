//! expanded-tree-json-v1 for trusted, already-expanded source observations only.
//! Not an XML/package parser, source eligibility check, signature or authority.
use super::engine_protocol::ProtocolError;
use sha2::{Digest, Sha256};
use std::fmt::Write;
#[derive(Clone, Debug)]
pub struct ExpandedNode {
    pub tag: String,
    pub attributes: Vec<(String, String)>,
    pub text: Option<String>,
    pub tail: Option<String>,
    pub children: Vec<ExpandedNode>,
}
const MAX_BYTES: usize = 262_144;
fn quoted(s: &str, out: &mut String) -> Result<(), ProtocolError> {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ' '..='~' => out.push(c),
            _ => {
                let mut units = [0u16; 2];
                for unit in c.encode_utf16(&mut units) {
                    write!(out, "\\u{unit:04x}").map_err(|_| ProtocolError::InvalidOperation)?;
                }
            }
        }
        if out.len() > MAX_BYTES {
            return Err(ProtocolError::InvalidOperation);
        }
    }
    out.push('"');
    Ok(())
}
fn optional(s: &Option<String>, out: &mut String) -> Result<(), ProtocolError> {
    match s {
        Some(s) => quoted(s, out),
        None => {
            out.push_str("null");
            Ok(())
        }
    }
}
fn form(
    n: &ExpandedNode,
    out: &mut String,
    depth: usize,
    count: &mut usize,
) -> Result<(), ProtocolError> {
    *count += 1;
    if depth > 64 || *count > 2048 || n.tag.is_empty() || n.attributes.len() > 128 {
        return Err(ProtocolError::InvalidOperation);
    }
    out.push('[');
    quoted(&n.tag, out)?;
    out.push_str(",[");
    let mut attrs: Vec<_> = n.attributes.iter().collect();
    attrs.sort();
    if attrs.windows(2).any(|p| p[0].0 == p[1].0) {
        return Err(ProtocolError::InvalidOperation);
    }
    for (i, (key, value)) in attrs.into_iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push('[');
        quoted(key, out)?;
        out.push(',');
        quoted(value, out)?;
        out.push(']');
    }
    out.push_str("],");
    optional(&n.text, out)?;
    out.push(',');
    optional(&n.tail, out)?;
    out.push_str(",[");
    for (i, child) in n.children.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        form(child, out, depth + 1, count)?;
    }
    out.push_str("]]");
    if out.len() > MAX_BYTES {
        return Err(ProtocolError::InvalidOperation);
    }
    Ok(())
}
pub fn canonical_tree_bytes(node: &ExpandedNode) -> Result<Vec<u8>, ProtocolError> {
    let mut out = String::new();
    form(node, &mut out, 0, &mut 0)?;
    Ok(out.into_bytes())
}
pub fn local_fingerprint(node: &ExpandedNode) -> Result<String, ProtocolError> {
    Ok(Sha256::digest(canonical_tree_bytes(node)?)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}
