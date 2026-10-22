//! Format declarations are not evidence that an engine is installed or evaluated.
use std::collections::BTreeMap;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DocumentFormat {
    Docx,
    Pptx,
    Xlsx,
    Pdf,
    Doc,
    Ppt,
    Xls,
    Unknown,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DocumentOperation {
    Inspect,
    ReadText,
    Render,
    Annotate,
    StructuredEdit,
    Recalculate,
    Validate,
    Export,
    Sync,
}
impl DocumentOperation {
    pub(crate) fn is_read(self) -> bool {
        matches!(self, Self::Inspect | Self::ReadText | Self::Render)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CapabilityStatus {
    Supported,
    ReadOnly,
    Unsupported,
    NeedsLicense,
    NeedsNetwork,
    Unknown,
}

/// Host-owned evidence projection. Do not populate from extensions, a model's
/// claims, MIME routing, or the existence of these enum variants. This module
/// supplies no production matrix with a supported engine.
#[derive(Clone, Debug, Default)]
pub struct CapabilityMatrix {
    entries: BTreeMap<(DocumentFormat, DocumentOperation), CapabilityStatus>,
}
impl CapabilityMatrix {
    pub fn set(
        &mut self,
        format: DocumentFormat,
        operation: DocumentOperation,
        status: CapabilityStatus,
    ) {
        self.entries.insert((format, operation), status);
    }
    pub fn status(&self, format: DocumentFormat, operation: DocumentOperation) -> CapabilityStatus {
        self.entries
            .get(&(format, operation))
            .copied()
            .unwrap_or(CapabilityStatus::Unknown)
    }
}
