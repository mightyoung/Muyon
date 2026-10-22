//! Bounded text extraction (read-only), parity with the Kotlin preview: text only, no drawing,
//! no formula calculation (cached formula values are flagged), no embedded payloads.

use crate::error::{OfficeError, Result};
use crate::package::{Format, Package};
use crate::xml::{Kind, Tok, NS_A, NS_S, NS_W};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Section {
    pub name: String,
    pub text: String,
}

fn trailing_number(name: &str) -> u64 {
    let stem = name.strip_suffix(".xml").unwrap_or(name);
    let digits: String = stem.chars().rev().take_while(|c| c.is_ascii_digit()).collect::<Vec<_>>().into_iter().rev().collect();
    digits.parse().unwrap_or(0)
}

impl Package {
    pub fn extract_text(&self) -> Result<Vec<Section>> {
        let format = self.format().ok_or(OfficeError::UnsupportedFormat)?;
        let mut parts: Vec<&String> = self
            .part_names()
            .iter()
            .filter(|n| match format {
                Format::Docx => n.as_str() == "word/document.xml",
                Format::Pptx => is_numbered(n, "ppt/slides/slide"),
                Format::Xlsx => is_numbered(n, "xl/worksheets/sheet"),
            })
            .collect();
        parts.sort_by_key(|n| trailing_number(n));
        if parts.is_empty() || parts.len() > self.limits.max_sections {
            return Err(OfficeError::Unsupported("missing or too many content parts"));
        }
        let shared = if format == Format::Xlsx && self.has_part("xl/sharedStrings.xml") {
            self.shared_strings()?
        } else {
            Vec::new()
        };
        let mut total = 0usize;
        let mut out = Vec::new();
        for name in parts {
            let (_, toks) = self.tokens(name)?;
            let text = match format {
                Format::Docx => paragraphs(&toks, NS_W, "t", "p", "br"),
                Format::Pptx => paragraphs(&toks, NS_A, "t", "p", "br"),
                Format::Xlsx => sheet_text(&toks, &shared)?,
            };
            total += text.len();
            if total > self.limits.max_text {
                return Err(OfficeError::LimitExceeded("text size"));
            }
            out.push(Section {
                name: name.clone(),
                text: if text.trim().is_empty() { "此部分没有可预览文本".to_owned() } else { text },
            });
        }
        Ok(out)
    }

    fn shared_strings(&self) -> Result<Vec<String>> {
        let (_, toks) = self.tokens("xl/sharedStrings.xml")?;
        let mut out = Vec::new();
        let mut cur = String::new();
        let mut in_si = false;
        let mut phonetic = 0usize;
        let mut chars = 0usize;
        for (k, t) in toks.iter().enumerate() {
            if t.is(Kind::Start, NS_S, "si") {
                in_si = true;
                cur.clear();
            } else if t.is(Kind::End, NS_S, "si") {
                chars += cur.len();
                if out.len() >= 10_000 || chars > self.limits.max_text {
                    return Err(OfficeError::LimitExceeded("shared strings"));
                }
                out.push(core::mem::take(&mut cur));
                in_si = false;
            } else if t.is(Kind::Start, NS_S, "rPh") {
                phonetic += 1;
            } else if t.is(Kind::End, NS_S, "rPh") {
                phonetic = phonetic.saturating_sub(1);
            } else if in_si && phonetic == 0 && t.is(Kind::Start, NS_S, "t") {
                if let Some((text, _, _)) = crate::xml::simple_text(&toks, k) {
                    cur.push_str(&text);
                }
            }
        }
        Ok(out)
    }
}

fn is_numbered(name: &str, prefix: &str) -> bool {
    name.strip_prefix(prefix)
        .and_then(|r| r.strip_suffix(".xml"))
        .map(|d| !d.is_empty() && d.len() <= 6 && !d.starts_with('0') && d.chars().all(|c| c.is_ascii_digit()))
        .unwrap_or(false)
}

fn paragraphs(toks: &[Tok], ns: &str, t: &str, p: &str, br: &str) -> String {
    let mut out = String::new();
    for (k, tok) in toks.iter().enumerate() {
        if tok.is(Kind::Start, ns, t) {
            if let Some((text, _, _)) = crate::xml::simple_text(toks, k) {
                out.push_str(&text);
            }
        } else if tok.is(Kind::End, ns, p) || tok.is(Kind::Empty, ns, br) || tok.is(Kind::End, ns, br) {
            out.push('\n');
        }
    }
    out
}

fn sheet_text(toks: &[Tok], shared: &[String]) -> Result<String> {
    let mut out = String::new();
    let mut k = 0;
    while k < toks.len() {
        let t = &toks[k];
        if t.is(Kind::Start, NS_S, "c") {
            let cell = t.attr("r").unwrap_or("").to_owned();
            let ty = t.attr("t").unwrap_or("").to_owned();
            let mut formula = false;
            let mut value = String::new();
            let mut j = k + 1;
            while j < toks.len() && !(toks[j].kind == Kind::End && toks[j].depth == t.depth) {
                let c = &toks[j];
                if c.is(Kind::Start, NS_S, "f") || c.is(Kind::Empty, NS_S, "f") {
                    formula = true;
                } else if c.is(Kind::Start, NS_S, "v") || c.is(Kind::Start, NS_S, "t") {
                    if let Some((text, _, _)) = crate::xml::simple_text(toks, j) {
                        value.push_str(&text);
                    }
                }
                j += 1;
            }
            let display = if ty == "s" {
                shared
                    .get(value.parse::<usize>().map_err(|_| OfficeError::MalformedXml("shared string index"))?)
                    .cloned()
                    .ok_or(OfficeError::MalformedXml("missing shared string"))?
            } else {
                value
            };
            out.push_str(&cell);
            out.push_str(": ");
            out.push_str(&display);
            if formula {
                out.push_str(" [公式缓存值]");
            }
            out.push('\n');
            k = j;
        }
        k += 1;
    }
    Ok(out)
}
