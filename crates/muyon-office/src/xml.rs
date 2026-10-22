//! Strict OOXML-subset XML tokenizer.
//!
//! Deliberately not a general XML parser: DOCTYPE and any non-predefined entity are rejected,
//! namespaces are resolved, and every token carries its exact byte span so callers can splice
//! replacement text while leaving every other byte of the part untouched.

use crate::error::{OfficeError, Result};

pub const NS_W: &str = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
pub const NS_A: &str = "http://schemas.openxmlformats.org/drawingml/2006/main";
pub const NS_S: &str = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
pub const NS_R: &str = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
pub const NS_PKG_REL: &str = "http://schemas.openxmlformats.org/package/2006/relationships";
const NS_XML: &str = "http://www.w3.org/XML/1998/namespace";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Start,
    End,
    Empty,
    Text,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attr {
    pub ns: Option<String>,
    pub local: String,
    pub value: String,
}

#[derive(Debug, Clone)]
pub struct Tok {
    pub kind: Kind,
    pub ns: Option<String>,
    pub local: String,
    pub attrs: Vec<Attr>,
    /// Decoded text (Text tokens only).
    pub text: String,
    /// Raw byte range `[start, end)` of the whole event in the source part.
    pub span: (usize, usize),
    /// True when the text contained a CDATA section (never spliced).
    pub cdata: bool,
    pub depth: usize,
}

impl Tok {
    pub fn is(&self, kind: Kind, ns: &str, local: &str) -> bool {
        self.kind == kind && self.ns.as_deref() == Some(ns) && self.local == local
    }
    pub fn attr(&self, local: &str) -> Option<&str> {
        self.attrs
            .iter()
            .find(|a| a.ns.is_none() && a.local == local)
            .map(|a| a.value.as_str())
    }
    pub fn attr_ns(&self, ns: &str, local: &str) -> Option<&str> {
        self.attrs
            .iter()
            .find(|a| a.ns.as_deref() == Some(ns) && a.local == local)
            .map(|a| a.value.as_str())
    }
}

pub struct XmlLimits {
    pub max_depth: usize,
    pub max_tokens: usize,
}

fn decode_entities(raw: &str, in_attr: bool) -> Result<String> {
    if !raw.contains('&') {
        if in_attr && raw.contains('<') {
            return Err(OfficeError::MalformedXml("'<' in attribute"));
        }
        return Ok(raw.to_owned());
    }
    let mut out = String::with_capacity(raw.len());
    let mut rest = raw;
    while let Some(p) = rest.find('&') {
        out.push_str(&rest[..p]);
        let after = &rest[p + 1..];
        let semi = after
            .find(';')
            .ok_or(OfficeError::MalformedXml("unterminated entity"))?;
        let name = &after[..semi];
        match name {
            "amp" => out.push('&'),
            "lt" => out.push('<'),
            "gt" => out.push('>'),
            "quot" => out.push('"'),
            "apos" => out.push('\''),
            _ if name.starts_with("#x") || name.starts_with("#X") => {
                out.push(char_ref(u32::from_str_radix(&name[2..], 16))?)
            }
            _ if name.starts_with('#') => out.push(char_ref(name[1..].parse::<u32>())?),
            _ => return Err(OfficeError::UnsupportedEntity),
        }
        rest = &after[semi + 1..];
    }
    out.push_str(rest);
    Ok(out)
}

fn char_ref(v: core::result::Result<u32, core::num::ParseIntError>) -> Result<char> {
    let c = v
        .ok()
        .and_then(char::from_u32)
        .ok_or(OfficeError::MalformedXml("bad character reference"))?;
    // XML 1.0 Char production.
    let ok = matches!(c, '\t' | '\n' | '\r') || (c >= ' ' && c != '\u{FFFE}' && c != '\u{FFFF}');
    if ok {
        Ok(c)
    } else {
        Err(OfficeError::MalformedXml("disallowed character reference"))
    }
}

struct Scope {
    qname: String,
    decls: Vec<(String, String)>,
}

fn lookup(scopes: &[Scope], prefix: &str) -> Option<String> {
    if prefix == "xml" {
        return Some(NS_XML.to_owned());
    }
    for s in scopes.iter().rev() {
        for (p, u) in s.decls.iter().rev() {
            if p == prefix {
                return if u.is_empty() { None } else { Some(u.clone()) };
            }
        }
    }
    None
}

fn is_name_end(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\r' | b'\n' | b'/' | b'>' | b'=')
}

pub fn tokenize(bytes: &[u8], limits: &XmlLimits) -> Result<Vec<Tok>> {
    let src = core::str::from_utf8(bytes).map_err(|_| OfficeError::MalformedXml("not UTF-8"))?;
    let b = src.as_bytes();
    let mut i = if src.starts_with('\u{FEFF}') { 3 } else { 0 };
    let mut toks: Vec<Tok> = Vec::new();
    let mut scopes: Vec<Scope> = Vec::new();
    let mut root_closed = false;
    let mut root_seen = false;

    while i < b.len() {
        if toks.len() > limits.max_tokens {
            return Err(OfficeError::LimitExceeded("xml tokens"));
        }
        if b[i] != b'<' {
            let end = src[i..].find('<').map(|p| i + p).unwrap_or(b.len());
            let raw = &src[i..end];
            if scopes.is_empty() {
                if !raw.trim().is_empty() {
                    return Err(OfficeError::MalformedXml("text outside root"));
                }
            } else {
                push_text(
                    &mut toks,
                    decode_entities(raw, false)?,
                    (i, end),
                    false,
                    scopes.len(),
                );
            }
            i = end;
            continue;
        }
        let rest = &src[i..];
        if rest.starts_with("<!--") {
            let end = rest
                .find("-->")
                .ok_or(OfficeError::MalformedXml("unterminated comment"))?;
            i += end + 3;
        } else if rest.starts_with("<![CDATA[") {
            let end = rest
                .find("]]>")
                .ok_or(OfficeError::MalformedXml("unterminated CDATA"))?;
            if scopes.is_empty() {
                return Err(OfficeError::MalformedXml("CDATA outside root"));
            }
            let text = rest[9..end].to_owned();
            push_text(&mut toks, text, (i, i + end + 3), true, scopes.len());
            i += end + 3;
        } else if rest.starts_with("<!") {
            return Err(OfficeError::DtdNotAllowed);
        } else if rest.starts_with("<?") {
            let end = rest
                .find("?>")
                .ok_or(OfficeError::MalformedXml("unterminated PI"))?;
            i += end + 2;
        } else if rest.starts_with("</") {
            let close = rest
                .find('>')
                .ok_or(OfficeError::MalformedXml("unterminated end tag"))?;
            let qname = rest[2..close].trim_end();
            let scope = scopes
                .pop()
                .ok_or(OfficeError::MalformedXml("unbalanced end tag"))?;
            if scope.qname != qname {
                return Err(OfficeError::MalformedXml("mismatched end tag"));
            }
            let (ns, local) = split_name(&scope_for_end(&scopes, &scope), qname)?;
            toks.push(Tok {
                kind: Kind::End,
                ns,
                local,
                attrs: Vec::new(),
                text: String::new(),
                span: (i, i + close + 1),
                cdata: false,
                depth: scopes.len(),
            });
            if scopes.is_empty() {
                root_closed = true;
            }
            i += close + 1;
        } else {
            if root_closed {
                return Err(OfficeError::MalformedXml("content after root"));
            }
            let start = i;
            let mut p = i + 1;
            let name_start = p;
            while p < b.len() && !is_name_end(b[p]) {
                p += 1;
            }
            if p == name_start {
                return Err(OfficeError::MalformedXml("empty tag name"));
            }
            let qname = src[name_start..p].to_owned();
            let mut raw_attrs: Vec<(String, String)> = Vec::new();
            let empty;
            loop {
                while p < b.len() && matches!(b[p], b' ' | b'\t' | b'\r' | b'\n') {
                    p += 1;
                }
                if p >= b.len() {
                    return Err(OfficeError::MalformedXml("unterminated start tag"));
                }
                if b[p] == b'>' {
                    empty = false;
                    p += 1;
                    break;
                }
                if b[p] == b'/' {
                    if b.get(p + 1) != Some(&b'>') {
                        return Err(OfficeError::MalformedXml("bad empty tag"));
                    }
                    empty = true;
                    p += 2;
                    break;
                }
                let an = p;
                while p < b.len() && !is_name_end(b[p]) {
                    p += 1;
                }
                let aname = src[an..p].to_owned();
                if aname.is_empty() {
                    return Err(OfficeError::MalformedXml("empty attribute name"));
                }
                while p < b.len() && matches!(b[p], b' ' | b'\t' | b'\r' | b'\n') {
                    p += 1;
                }
                if b.get(p) != Some(&b'=') {
                    return Err(OfficeError::MalformedXml("attribute without value"));
                }
                p += 1;
                while p < b.len() && matches!(b[p], b' ' | b'\t' | b'\r' | b'\n') {
                    p += 1;
                }
                let quote = *b.get(p).ok_or(OfficeError::MalformedXml("missing quote"))?;
                if quote != b'"' && quote != b'\'' {
                    return Err(OfficeError::MalformedXml("unquoted attribute"));
                }
                let vs = p + 1;
                let ve = src[vs..]
                    .find(quote as char)
                    .map(|q| vs + q)
                    .ok_or(OfficeError::MalformedXml("unterminated attribute"))?;
                if raw_attrs.iter().any(|(n, _)| *n == aname) {
                    return Err(OfficeError::MalformedXml("duplicate attribute"));
                }
                raw_attrs.push((aname, decode_entities(&src[vs..ve], true)?));
                p = ve + 1;
            }
            let mut decls = Vec::new();
            let mut plain: Vec<(String, String)> = Vec::new();
            for (n, v) in raw_attrs {
                if n == "xmlns" {
                    decls.push((String::new(), v));
                } else if let Some(pre) = n.strip_prefix("xmlns:") {
                    decls.push((pre.to_owned(), v));
                } else {
                    plain.push((n, v));
                }
            }
            scopes.push(Scope {
                qname: qname.clone(),
                decls,
            });
            let (ns, local) = split_name(&scopes, &qname)?;
            let mut attrs = Vec::new();
            for (n, v) in plain {
                let (ans, alocal) = match n.split_once(':') {
                    Some((pre, l)) => (
                        Some(
                            lookup(&scopes, pre)
                                .ok_or(OfficeError::MalformedXml("unknown prefix"))?,
                        ),
                        l.to_owned(),
                    ),
                    None => (None, n),
                };
                attrs.push(Attr {
                    ns: ans,
                    local: alocal,
                    value: v,
                });
            }
            if scopes.len() > limits.max_depth {
                return Err(OfficeError::LimitExceeded("xml depth"));
            }
            root_seen = true;
            let depth = scopes.len() - 1;
            if empty {
                scopes.pop();
                if scopes.is_empty() {
                    root_closed = true;
                }
            }
            toks.push(Tok {
                kind: if empty { Kind::Empty } else { Kind::Start },
                ns,
                local,
                attrs,
                text: String::new(),
                span: (start, p),
                cdata: false,
                depth,
            });
            i = p;
        }
    }
    if !scopes.is_empty() || !root_seen {
        return Err(OfficeError::MalformedXml("unbalanced document"));
    }
    Ok(toks)
}

fn scope_for_end(remaining: &[Scope], popped: &Scope) -> Vec<Scope> {
    // End-tag names must resolve with the popped element's own declarations in scope.
    let mut v: Vec<Scope> = remaining
        .iter()
        .map(|s| Scope {
            qname: s.qname.clone(),
            decls: s.decls.clone(),
        })
        .collect();
    v.push(Scope {
        qname: popped.qname.clone(),
        decls: popped.decls.clone(),
    });
    v
}

fn split_name(scopes: &[Scope], qname: &str) -> Result<(Option<String>, String)> {
    match qname.split_once(':') {
        Some((pre, local)) => Ok((
            Some(lookup(scopes, pre).ok_or(OfficeError::MalformedXml("unknown prefix"))?),
            local.to_owned(),
        )),
        None => Ok((lookup(scopes, ""), qname.to_owned())),
    }
}

fn push_text(toks: &mut Vec<Tok>, text: String, span: (usize, usize), cdata: bool, depth: usize) {
    if let Some(prev) = toks.last_mut() {
        if prev.kind == Kind::Text && prev.span.1 == span.0 {
            prev.text.push_str(&text);
            prev.span.1 = span.1;
            prev.cdata |= cdata;
            return;
        }
    }
    toks.push(Tok {
        kind: Kind::Text,
        ns: None,
        local: String::new(),
        attrs: Vec::new(),
        text,
        span,
        cdata,
        depth,
    });
}

/// For a `Start` token at `k`, return `(text, byte range of the text, is_plain)` when the element
/// contains only text (or nothing). Mixed content returns `None`.
pub fn simple_text(toks: &[Tok], k: usize) -> Option<(String, (usize, usize), bool)> {
    let start = toks.get(k)?;
    if start.kind != Kind::Start {
        return None;
    }
    match (toks.get(k + 1), toks.get(k + 2)) {
        (Some(e), _) if e.kind == Kind::End && e.depth == start.depth => {
            Some((String::new(), (start.span.1, start.span.1), true))
        }
        (Some(t), Some(e))
            if t.kind == Kind::Text && e.kind == Kind::End && e.depth == start.depth =>
        {
            Some((t.text.clone(), t.span, !t.cdata))
        }
        _ => None,
    }
}

/// Escape replacement text for element content.
pub fn escape_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            _ => out.push(c),
        }
    }
    out
}
