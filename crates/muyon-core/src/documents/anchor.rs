//! Revision-bound locations. Validation is structural, never target resolution.
use super::{identity::valid_id, DocumentFormat, DocumentRef, ReadInvalidation};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rect { pub x: f64, pub y: f64, pub width: f64, pub height: f64 }
impl Rect {
    fn valid(self) -> bool {
        [self.x, self.y, self.width, self.height, self.x + self.width, self.y + self.height].iter().all(|n| n.is_finite())
            && self.width > 0.0 && self.height > 0.0
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CoordinateSystem {
    Unknown,
    /// PDF user-space coordinates before page rotation; crop may have an offset.
    PdfUserSpace,
    /// Coordinates normalized to the unrotated crop, top-left origin, [0,1].
    CropNormalizedTopLeft,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PageRotation { Degrees0, Degrees90, Degrees180, Degrees270 }

#[derive(Clone, Debug, PartialEq)]
pub struct PdfAnchor {
    pub page_index_zero_based: Option<u32>,
    pub coordinates: CoordinateSystem,
    pub rotation: Option<PageRotation>,
    /// Unrotated PDF crop box in PDF user-space; None means unknown.
    pub crop: Option<Rect>,
    pub region: Rect,
}
#[derive(Clone, Debug, PartialEq)]
pub enum AnchorLocation {
    Pdf(PdfAnchor),
    Docx { part: String, paragraph_id: String },
    Pptx { slide_id: String, shape_id: String },
    /// Inclusive one-based OOXML cell range, stable sheet ID rather than index.
    Xlsx { sheet_id: String, first_row: u32, first_column: u32, last_row: u32, last_column: u32 },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AnchorStatus { StructurallyValid, UnresolvedGeometry }
#[derive(Clone, Debug, PartialEq)]
pub struct DocumentAnchor { pub document: DocumentRef, pub location: AnchorLocation }

impl DocumentAnchor {
    pub fn validate_for(&self, current: &DocumentRef) -> Result<AnchorStatus, ReadInvalidation> {
        self.document.matches(current)?;
        let valid = match (&self.location, current.format()) {
            (AnchorLocation::Pdf(p), DocumentFormat::Pdf) => {
                if !p.region.valid() || p.crop.is_some_and(|r| !r.valid()) {
                    return Err(ReadInvalidation::InvalidAnchor);
                }
                if p.coordinates == CoordinateSystem::CropNormalizedTopLeft
                    && (p.region.x < 0.0 || p.region.y < 0.0
                        || p.region.x + p.region.width > 1.0 || p.region.y + p.region.height > 1.0)
                {
                    return Err(ReadInvalidation::InvalidAnchor);
                }
                if p.coordinates == CoordinateSystem::Unknown || p.rotation.is_none()
                    || p.crop.is_none() || p.page_index_zero_based.is_none()
                {
                    return Ok(AnchorStatus::UnresolvedGeometry);
                }
                true
            }
            (AnchorLocation::Docx { part, paragraph_id }, DocumentFormat::Docx) => {
                // OPC part identifier only, never a filesystem path to open.
                !part.is_empty() && part.len() <= 1024
                    && !part.contains(['\\', ':', '\0'])
                    && part.split('/').all(|s| !s.is_empty() && s != "." && s != ".." && !s.chars().any(char::is_control))
                    && valid_id(paragraph_id)
            }
            (AnchorLocation::Pptx { slide_id, shape_id }, DocumentFormat::Pptx) => valid_id(slide_id) && valid_id(shape_id),
            (AnchorLocation::Xlsx { sheet_id, first_row, first_column, last_row, last_column }, DocumentFormat::Xlsx) => {
                valid_id(sheet_id) && *first_row >= 1 && first_row <= last_row && *last_row <= 1_048_576
                    && *first_column >= 1 && first_column <= last_column && *last_column <= 16_384
            }
            _ => return Err(ReadInvalidation::FormatMismatch),
        };
        if valid { Ok(AnchorStatus::StructurallyValid) } else { Err(ReadInvalidation::InvalidAnchor) }
    }
}
