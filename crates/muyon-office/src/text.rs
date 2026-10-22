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
    let digits: String = stem
        .chars()
        .rev()
        .take_while(|c| c.is_ascii_digit())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    digits.parse().unwrap_or(0)
}

impl Package {
    pub fn extract_text(&self) -> Result<Vec<Section>> {
        self.extract_text_replacing(None)
    }

    pub(crate) fn extract_text_replacing(
        &self,
        replacement: Option<(&str, &[u8])>,
    ) -> Result<Vec<Section>> {
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
            return Err(OfficeError::Unsupported(
                "missing or too many content parts",
            ));
        }
        let shared = if format == Format::Xlsx && self.has_part("xl/sharedStrings.xml") {
            self.shared_strings(replacement)?
        } else {
            Vec::new()
        };
        let mut total = 0usize;
        let mut out = Vec::new();
        for name in parts {
            let toks = self.text_tokens(name, replacement)?;
            let remaining = self.limits.max_text.saturating_sub(total);
            let text = match format {
                Format::Docx => paragraphs(&toks, NS_W, "t", "p", "br", remaining)?,
                Format::Pptx => paragraphs(&toks, NS_A, "t", "p", "br", remaining)?,
                Format::Xlsx => sheet_text(&toks, &shared, remaining)?,
            };
            let text = if text.trim().is_empty() {
                let placeholder = "此部分没有可预览文本";
                if placeholder.len() > remaining {
                    return Err(OfficeError::LimitExceeded("text size"));
                }
                placeholder.to_owned()
            } else {
                text
            };
            total += text.len(); // text was bounded by remaining before appending
            out.push(Section {
                name: name.clone(),
                text,
            });
        }
        Ok(out)
    }

    fn text_tokens(&self, name: &str, replacement: Option<(&str, &[u8])>) -> Result<Vec<Tok>> {
        if let Some((target, bytes)) = replacement {
            if target == name {
                return crate::xml::tokenize(
                    bytes,
                    &crate::xml::XmlLimits {
                        max_depth: self.limits.max_xml_depth,
                        max_tokens: self.limits.max_xml_tokens,
                    },
                );
            }
        }
        self.tokens(name).map(|(_, tokens)| tokens)
    }

    fn shared_strings(&self, replacement: Option<(&str, &[u8])>) -> Result<Vec<String>> {
        let toks = self.text_tokens("xl/sharedStrings.xml", replacement)?;
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
                    append_text(&mut cur, &text, self.limits.max_text.saturating_sub(chars))?;
                }
            }
        }
        Ok(out)
    }
}

fn is_numbered(name: &str, prefix: &str) -> bool {
    name.strip_prefix(prefix)
        .and_then(|r| r.strip_suffix(".xml"))
        .map(|d| {
            !d.is_empty()
                && d.len() <= 6
                && !d.starts_with('0')
                && d.chars().all(|c| c.is_ascii_digit())
        })
        .unwrap_or(false)
}

fn append_text(out: &mut String, text: &str, limit: usize) -> Result<()> {
    if text.len() > limit.saturating_sub(out.len()) {
        return Err(OfficeError::LimitExceeded("text size"));
    }
    out.try_reserve_exact(text.len())
        .map_err(|_| OfficeError::LimitExceeded("text size"))?;
    out.push_str(text);
    Ok(())
}

fn paragraphs(toks: &[Tok], ns: &str, t: &str, p: &str, br: &str, limit: usize) -> Result<String> {
    let mut out = String::new();
    for (k, tok) in toks.iter().enumerate() {
        if tok.is(Kind::Start, ns, t) {
            if let Some((text, _, _)) = crate::xml::simple_text(toks, k) {
                append_text(&mut out, &text, limit)?;
            }
        } else if tok.is(Kind::End, ns, p)
            || tok.is(Kind::Empty, ns, br)
            || tok.is(Kind::End, ns, br)
        {
            append_text(&mut out, "\n", limit)?;
        }
    }
    Ok(out)
}

fn sheet_text(toks: &[Tok], shared: &[String], limit: usize) -> Result<String> {
    let mut out = String::new();
    let mut k = 0;
    while k < toks.len() {
        let t = &toks[k];
        if t.is(Kind::Start, NS_S, "c") {
            let cell = t.attr("r").unwrap_or("").to_owned();
            let ty = t.attr("t").unwrap_or("").to_owned();
            let mut formula = false;
            let mut phonetic = 0usize;
            let mut value = String::new();
            let mut j = k + 1;
            while j < toks.len() && !(toks[j].kind == Kind::End && toks[j].depth == t.depth) {
                let c = &toks[j];
                if c.is(Kind::Start, NS_S, "rPh") {
                    phonetic += 1;
                } else if c.is(Kind::End, NS_S, "rPh") {
                    phonetic = phonetic.saturating_sub(1);
                } else if c.is(Kind::Start, NS_S, "f") || c.is(Kind::Empty, NS_S, "f") {
                    formula = true;
                } else if phonetic == 0
                    && (c.is(Kind::Start, NS_S, "v") || c.is(Kind::Start, NS_S, "t"))
                {
                    if let Some((text, _, _)) = crate::xml::simple_text(toks, j) {
                        append_text(&mut value, &text, limit)?;
                    }
                }
                j += 1;
            }
            let display = if ty == "s" {
                shared
                    .get(
                        value
                            .parse::<usize>()
                            .map_err(|_| OfficeError::MalformedXml("shared string index"))?,
                    )
                    .cloned()
                    .ok_or(OfficeError::MalformedXml("missing shared string"))?
            } else {
                value
            };
            append_text(&mut out, &cell, limit)?;
            append_text(&mut out, ": ", limit)?;
            append_text(&mut out, &display, limit)?;
            if formula {
                append_text(&mut out, " [公式缓存值]", limit)?;
            }
            append_text(&mut out, "\n", limit)?;
            k = j;
        }
        k += 1;
    }
    Ok(out)
}
