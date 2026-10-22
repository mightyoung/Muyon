//! Narrow, pre-declared edits: one DOCX run of text, one XLSX numeric cell.
//! Both require the caller's `expected` value to match exactly once; no guessing.

use crate::error::{OfficeError, Result};
use crate::package::{splice, splice_size, EditReceipt, Package};
use crate::xml::{escape_text, simple_text, Kind, Tok, NS_PKG_REL, NS_R, NS_S, NS_W};

const WORD_MAIN: &str = "word/document.xml";

fn valid_text(s: &str) -> bool {
    s.chars()
        .all(|c| (c >= ' ' || c == '\t') && c != '\u{FFFE}' && c != '\u{FFFF}' && c != '\u{FEFF}')
}

impl Package {
    /// Replace the text of exactly one `w:t` run in `word/document.xml`.
    /// `expected` is the full current text of that run and must be unique in the part.
    pub fn replace_docx_run_text(&self, expected: &str, replacement: &str) -> Result<EditReceipt> {
        if self.format() != Some(crate::package::Format::Docx) {
            return Err(OfficeError::UnsupportedFormat);
        }
        self.check_edit_inputs(&[expected, replacement])?;
        if expected.is_empty() {
            return Err(OfficeError::InvalidReplacement("expected text is empty"));
        }
        if replacement.is_empty() || !valid_text(replacement) {
            return Err(OfficeError::InvalidReplacement(
                "replacement empty or has control characters",
            ));
        }
        let (bytes, toks) = self.tokens(WORD_MAIN)?;
        let mut hits: Vec<(usize, (usize, usize))> = Vec::new();
        for (k, t) in toks.iter().enumerate() {
            if t.is(Kind::Start, NS_W, "t") {
                if let Some((text, range, plain)) = simple_text(&toks, k) {
                    if plain && text == expected {
                        hits.push((k, range));
                    }
                }
            }
        }
        let (k, range) = match hits.as_slice() {
            [] => return Err(OfficeError::NotFound),
            [one] => *one,
            _ => return Err(OfficeError::Ambiguous),
        };
        let preserves = toks[k]
            .attr_ns("http://www.w3.org/XML/1998/namespace", "space")
            .map(|v| v == "preserve")
            .unwrap_or(false);
        if replacement.trim() != replacement && !preserves {
            return Err(OfficeError::InvalidReplacement(
                "leading/trailing whitespace needs xml:space=preserve on the run",
            ));
        }
        let escaped_size = replacement.bytes().try_fold(0usize, |n, b| {
            n.checked_add(match b {
                b'&' => 5,
                b'<' | b'>' => 4,
                _ => 1,
            })
            .ok_or(OfficeError::LimitExceeded("part size"))
        })?;
        self.check_rewrite_size(WORD_MAIN, splice_size(bytes.len(), range, escaped_size)?)?;
        let patched = splice(&bytes, range, escape_text(replacement).as_bytes())?;
        self.rewrite_part(WORD_MAIN, &patched, range)
    }

    /// Set one plain numeric value cell (no formula, no shared/inline string, visible sheet).
    /// Cached values of dependent formulas are NOT recalculated; callers must not claim so.
    pub fn set_xlsx_numeric_cell(
        &self,
        sheet: &str,
        cell: &str,
        expected: &str,
        replacement: &str,
    ) -> Result<EditReceipt> {
        if self.format() != Some(crate::package::Format::Xlsx) {
            return Err(OfficeError::UnsupportedFormat);
        }
        self.check_edit_inputs(&[sheet, cell, expected, replacement])?;
        if !is_cell_ref(cell) {
            return Err(OfficeError::InvalidReplacement("cell reference"));
        }
        if !is_plain_number(expected) || !is_plain_number(replacement) {
            return Err(OfficeError::InvalidReplacement(
                "value must be a plain finite number",
            ));
        }
        let part = self.resolve_sheet(sheet)?;
        let (bytes, toks) = self.tokens(&part)?;
        let mut hits: Vec<(usize, (usize, usize))> = Vec::new();
        let mut k = 0;
        while k < toks.len() {
            let t = &toks[k];
            if t.is(Kind::Start, NS_S, "c") && t.attr("r") == Some(cell) {
                let mut j = k + 1;
                let mut value: Option<(String, (usize, usize))> = None;
                let mut other = false;
                while j < toks.len() && !(toks[j].kind == Kind::End && toks[j].depth == t.depth) {
                    let c = &toks[j];
                    if c.depth == t.depth + 1 && c.kind != Kind::Text {
                        if c.is(Kind::Start, NS_S, "v") {
                            if let Some((text, range, plain)) = simple_text(&toks, j) {
                                if plain {
                                    value = Some((text, range));
                                } else {
                                    other = true;
                                }
                            } else {
                                other = true;
                            }
                        } else if c.local == "f" || c.local == "is" {
                            return Err(OfficeError::Unsupported("formula or inline-string cell"));
                        } else if !c.is(Kind::End, NS_S, "v") {
                            other = true;
                        }
                    }
                    j += 1;
                }
                if !matches!(t.attr("t"), None | Some("n")) {
                    return Err(OfficeError::Unsupported("non-numeric cell type"));
                }
                if other {
                    return Err(OfficeError::Unsupported("unexpected cell content"));
                }
                if let Some((text, range)) = value {
                    if text == expected {
                        hits.push((k, range));
                    }
                }
                k = j;
            }
            k += 1;
        }
        let (_, range) = match hits.as_slice() {
            [] => return Err(OfficeError::NotFound),
            [one] => *one,
            _ => return Err(OfficeError::Ambiguous),
        };
        self.check_rewrite_size(&part, splice_size(bytes.len(), range, replacement.len())?)?;
        let patched = splice(&bytes, range, replacement.as_bytes())?;
        self.rewrite_part(&part, &patched, range)
    }

    fn check_edit_inputs(&self, inputs: &[&str]) -> Result<()> {
        if inputs
            .iter()
            .any(|s| s.len() > self.limits.max_text || s.len() > self.limits.max_part)
        {
            return Err(OfficeError::LimitExceeded("edit input size"));
        }
        Ok(())
    }

    fn resolve_sheet(&self, name: &str) -> Result<String> {
        let (_, wb) = self.tokens("xl/workbook.xml")?;
        let mut found: Vec<&Tok> = wb
            .iter()
            .filter(|t| t.is(Kind::Start, NS_S, "sheet") || t.is(Kind::Empty, NS_S, "sheet"))
            .filter(|t| t.attr("name") == Some(name))
            .collect();
        let sheet = match found.len() {
            0 => return Err(OfficeError::NotFound),
            1 => found.remove(0),
            _ => return Err(OfficeError::Ambiguous),
        };
        if !matches!(sheet.attr("state"), None | Some("visible")) {
            return Err(OfficeError::Unsupported("hidden sheet"));
        }
        let rid = sheet
            .attr_ns(NS_R, "id")
            .ok_or(OfficeError::Unsupported("sheet without relationship id"))?;
        let (_, rels) = self.tokens("xl/_rels/workbook.xml.rels")?;
        let rel = rels
            .iter()
            .find(|t| {
                (t.is(Kind::Start, NS_PKG_REL, "Relationship")
                    || t.is(Kind::Empty, NS_PKG_REL, "Relationship"))
                    && t.attr("Id") == Some(rid)
            })
            .ok_or(OfficeError::NotFound)?;
        if rel.attr("TargetMode") == Some("External") {
            return Err(OfficeError::Unsupported("external sheet target"));
        }
        if !rel
            .attr("Type")
            .map(|t| t.ends_with("/worksheet"))
            .unwrap_or(false)
        {
            return Err(OfficeError::Unsupported("not a worksheet relationship"));
        }
        let target = rel.attr("Target").ok_or(OfficeError::NotFound)?;
        let path = match target.strip_prefix('/') {
            Some(abs) => abs.to_owned(),
            None => format!("xl/{target}"),
        };
        if path
            .split('/')
            .any(|s| s == ".." || s == "." || s.is_empty())
            || path.contains('\\')
        {
            return Err(OfficeError::UnsafePath);
        }
        if !self.has_part(&path) {
            return Err(OfficeError::MissingPart(path));
        }
        Ok(path)
    }
}

fn is_cell_ref(s: &str) -> bool {
    let letters = s.chars().take_while(|c| c.is_ascii_uppercase()).count();
    let digits = &s[letters..];
    (1..=3).contains(&letters)
        && !digits.is_empty()
        && digits.len() <= 7
        && !digits.starts_with('0')
        && digits.chars().all(|c| c.is_ascii_digit())
}

fn is_plain_number(s: &str) -> bool {
    let body = s.strip_prefix(['-', '+']).unwrap_or(s);
    let (mant, exp) = match body.split_once(['e', 'E']) {
        Some((m, e)) => (m, Some(e)),
        None => (body, None),
    };
    let (int, frac) = match mant.split_once('.') {
        Some((i, f)) => (i, Some(f)),
        None => (mant, None),
    };
    let digits = |x: &str| !x.is_empty() && x.chars().all(|c| c.is_ascii_digit());
    let exp_ok = match exp {
        None => true,
        Some(e) => digits(e.strip_prefix(['-', '+']).unwrap_or(e)),
    };
    digits(int)
        && frac.map(digits).unwrap_or(true)
        && exp_ok
        && s.parse::<f64>().map(f64::is_finite).unwrap_or(false)
}
