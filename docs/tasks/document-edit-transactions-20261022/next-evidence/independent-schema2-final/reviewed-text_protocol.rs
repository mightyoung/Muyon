//! Held schema2 text mapping from trusted expanded run observations.
//! No package parser, part/relationship eligibility attestation or engine exists.
use super::{
    engine_protocol::{prepare_envelope, PreparedEngineRequest, ProtocolError},
    fingerprint::{local_fingerprint, ExpandedNode},
};
use crate::documents::{DocumentFormat, DocumentMetadata};
#[derive(Clone, Debug)]
pub enum TextLocation {
    DocxRun {
        paragraph_index: u32,
        run_index: u32,
    },
    PptxShape {
        part: String,
        slide_id: u32,
        shape_id: u32,
        paragraph_index: u32,
        run_index: u32,
    },
}
#[derive(Clone, Debug)]
pub struct TextEdit {
    pub location: TextLocation,
    pub observed_run: ExpandedNode,
    pub expected: String,
    pub replacement: String,
}
fn valid_text(s: &str) -> bool {
    (1..=512).contains(&s.chars().count())
        && !s
            .chars()
            .any(|c| (c as u32) < 32 || matches!(c, '\u{fffe}' | '\u{ffff}'))
}
fn slide_part(s: &str) -> bool {
    let Some(n) = s
        .strip_prefix("ppt/slides/slide")
        .and_then(|s| s.strip_suffix(".xml"))
    else {
        return false;
    };
    (1..=5).contains(&n.len()) && !n.starts_with('0') && n.bytes().all(|b| b.is_ascii_digit())
}
pub fn prepare_text_request_trusted(
    source: &DocumentMetadata,
    intent: &str,
    edit: TextEdit,
) -> Result<PreparedEngineRequest, ProtocolError> {
    if !valid_text(&edit.expected)
        || !valid_text(&edit.replacement)
        || edit.expected == edit.replacement
    {
        return Err(ProtocolError::InvalidOperation);
    }
    let (ns, part, kind, p, r) = match &edit.location {
        TextLocation::DocxRun {
            paragraph_index,
            run_index,
        } if source.document.format() == DocumentFormat::Docx => (
            "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
            "word/document.xml",
            "replace_docx_run_text",
            *paragraph_index,
            *run_index,
        ),
        TextLocation::PptxShape {
            part,
            slide_id,
            shape_id,
            paragraph_index,
            run_index,
        } if source.document.format() == DocumentFormat::Pptx
            && slide_part(part)
            && (1..=i32::MAX as u32).contains(slide_id)
            && (1..=i32::MAX as u32).contains(shape_id)
            && *paragraph_index == 0
            && *run_index == 0 =>
        {
            (
                "http://schemas.openxmlformats.org/drawingml/2006/main",
                part.as_str(),
                "replace_pptx_shape_text",
                *paragraph_index,
                *run_index,
            )
        }
        _ => return Err(ProtocolError::InvalidOperation),
    };
    if p > 9999 || r > 9999 || edit.observed_run.tag != format!("{{{ns}}}r") {
        return Err(ProtocolError::InvalidOperation);
    }
    let text: Vec<_> = edit
        .observed_run
        .children
        .iter()
        .filter(|n| n.tag == format!("{{{ns}}}t"))
        .collect();
    if text.len() != 1
        || text[0].text.as_deref() != Some(&edit.expected)
        || !text[0].children.is_empty()
    {
        return Err(ProtocolError::InvalidOperation);
    }
    if edit.replacement.trim() != edit.replacement
        && !text[0]
            .attributes
            .iter()
            .any(|(k, v)| k == "{http://www.w3.org/XML/1998/namespace}space" && v == "preserve")
    {
        return Err(ProtocolError::InvalidOperation);
    }
    let fingerprint = local_fingerprint(&edit.observed_run)?;
    let mut op = serde_json::json!({"kind":kind,"part":part,"paragraph_index":p,"run_index":r,"target_sha256":fingerprint,"expected":edit.expected,"replacement":edit.replacement});
    if let TextLocation::PptxShape {
        slide_id, shape_id, ..
    } = edit.location
    {
        op["slide_id"] = slide_id.into();
        op["shape_id"] = shape_id.into();
    }
    prepare_envelope(source, intent, 2, op)
}
