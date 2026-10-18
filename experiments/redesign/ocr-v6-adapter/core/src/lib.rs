use serde::{Deserialize, Serialize};
pub const TINY_VERSION: &str = "PP-OCRv6_tiny-det-2ba1506c-rec-2612ab37";
pub const PARAMETERS_VERSION: &str = "ppocr-android-dab3fe35-defaults-v1";
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DocumentRef {
    pub scope: String,
    pub document_id: String,
    pub revision: u64,
    pub source_digest: String,
    pub blob_ref: String,
}
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoordinateSpace {
    PdfPoints,
    ImagePixels,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RasterRef {
    pub digest: String,
    pub page_index: u32,
    pub width: u32,
    pub height: u32,
    pub exif_orientation: u8,
    pub source_width: f64,
    pub source_height: f64,
    pub coordinate_space: CoordinateSpace,
    pub raster_to_source: [f64; 9],
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Request {
    pub job_id: String,
    pub document: DocumentRef,
    pub raster: RasterRef,
    pub model_version: String,
    pub parameters_version: String,
    pub expires_at_ms: u64,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Line {
    pub text: String,
    pub quad: [[f64; 2]; 4],
    pub recognition_confidence: f64,
    pub detection_confidence: Option<f64>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlatformPage {
    pub job_id: String,
    pub raster_digest: String,
    pub model_version: String,
    pub parameters_version: String,
    pub width: u32,
    pub height: u32,
    pub lines: Vec<Line>,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ValidatedPage {
    pub request: Request,
    pub lines: Vec<Line>,
    pub extracted_at_ms: u64,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum State {
    Pending,
    Cancelled,
    Completed,
    Failed,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Error {
    InvalidRequest,
    InvalidResult,
    SourceUnavailable,
    Timeout,
    Terminal,
}
pub trait SourceAuthority {
    fn allows_ocr(&self, request: &Request) -> bool;
}
pub trait ResultStore {
    fn commit_if_current(&mut self, request: &Request, page: &ValidatedPage) -> Result<(), Error>;
}
pub struct Task {
    request: Request,
    state: State,
}
impl Task {
    /// Called only by the Rust application Service after obtaining W1's source snapshot.
    pub fn begin(
        request: Request,
        now_ms: u64,
        authority: &impl SourceAuthority,
    ) -> Result<Self, Error> {
        let r = &request.raster;
        if request.job_id.is_empty()
            || request.job_id.len() > 128
            || request.document.scope.is_empty()
            || request.document.document_id.is_empty()
            || request.document.blob_ref.is_empty()
            || !digest(&request.document.source_digest)
            || !digest(&r.digest)
            || r.width == 0
            || r.height == 0
            || r.width > 4096
            || r.height > 4096
            || u64::from(r.width) * u64::from(r.height) > 16_000_000
            || !(1..=8).contains(&r.exif_orientation)
            || !r.source_width.is_finite()
            || !r.source_height.is_finite()
            || r.source_width <= 0.
            || r.source_height <= 0.
            || request.model_version != TINY_VERSION
            || request.parameters_version != PARAMETERS_VERSION
            || request.expires_at_ms <= now_ms
            || request.expires_at_ms - now_ms > 120_000
            || !valid_transform(r)
        {
            return Err(Error::InvalidRequest);
        }
        if !authority.allows_ocr(&request) {
            return Err(Error::SourceUnavailable);
        }
        Ok(Self {
            request,
            state: State::Pending,
        })
    }
    pub fn state(&self) -> State {
        self.state
    }
    pub fn cancel(&mut self) {
        if self.state == State::Pending {
            self.state = State::Cancelled;
        }
    }
    /// This must run on the same serialized Rust task owner as cancel().
    /// The store atomically rechecks source revision/digest/grant and writes extraction only.
    pub fn accept(
        &mut self,
        page: PlatformPage,
        now_ms: u64,
        authority: &impl SourceAuthority,
        store: &mut impl ResultStore,
    ) -> Result<(), Error> {
        if self.state != State::Pending {
            return Err(Error::Terminal);
        }
        // Every attempted completion is terminal, including validation and storage failures.
        self.state = State::Failed;
        if now_ms >= self.request.expires_at_ms {
            return Err(Error::Timeout);
        }
        if !authority.allows_ocr(&self.request) {
            return Err(Error::SourceUnavailable);
        }
        let r = &self.request;
        if page.job_id != r.job_id
            || page.raster_digest != r.raster.digest
            || page.model_version != r.model_version
            || page.parameters_version != r.parameters_version
            || page.width != r.raster.width
            || page.height != r.raster.height
            || page.lines.len() > 3000
        {
            return Err(Error::InvalidResult);
        }
        let mut total_text = 0usize;
        let mut lines = page.lines;
        for line in &mut lines {
            total_text = total_text.saturating_add(line.text.len());
            if line.text.len() > 65_536
                || total_text > 1_048_576
                || !confidence(line.recognition_confidence)
                || line.detection_confidence.is_some_and(|v| !confidence(v))
                || !valid_quad(&line.quad, r.raster.width as f64, r.raster.height as f64)
            {
                return Err(Error::InvalidResult);
            }
            for point in &mut line.quad {
                *point = project(r.raster.raster_to_source, *point).ok_or(Error::InvalidResult)?;
            }
            if !valid_quad(&line.quad, r.raster.source_width, r.raster.source_height) {
                return Err(Error::InvalidResult);
            }
        }
        let page = ValidatedPage {
            request: r.clone(),
            lines,
            extracted_at_ms: now_ms,
        };
        store.commit_if_current(r, &page)?;
        self.state = State::Completed;
        Ok(())
    }
}
fn digest(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
fn confidence(v: f64) -> bool {
    v.is_finite() && (0.0..=1.0).contains(&v)
}
fn valid_quad(q: &[[f64; 2]; 4], width: f64, height: f64) -> bool {
    if q.iter().any(|p| {
        !p[0].is_finite()
            || !p[1].is_finite()
            || p[0] < 0.
            || p[0] > width
            || p[1] < 0.
            || p[1] > height
    }) {
        return false;
    }
    let crosses: Vec<f64> = (0..4)
        .map(|i| {
            let a = q[i];
            let b = q[(i + 1) % 4];
            let c = q[(i + 2) % 4];
            (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        })
        .collect();
    crosses.iter().all(|v| *v > 1e-9) || crosses.iter().all(|v| *v < -1e-9)
}
fn project(m: [f64; 9], p: [f64; 2]) -> Option<[f64; 2]> {
    let w = m[6] * p[0] + m[7] * p[1] + m[8];
    if !w.is_finite() || w.abs() < 1e-12 {
        return None;
    }
    let result = [
        (m[0] * p[0] + m[1] * p[1] + m[2]) / w,
        (m[3] * p[0] + m[4] * p[1] + m[5]) / w,
    ];
    if result.iter().all(|v| v.is_finite()) {
        Some(result)
    } else {
        None
    }
}
fn valid_transform(r: &RasterRef) -> bool {
    let m = r.raster_to_source;
    if m.iter().any(|v| !v.is_finite()) {
        return false;
    }
    let det = m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6])
        + m[2] * (m[3] * m[7] - m[4] * m[6]);
    if det.abs() < 1e-12 {
        return false;
    }
    let corners = [
        [0., 0.],
        [r.width as f64, 0.],
        [r.width as f64, r.height as f64],
        [0., r.height as f64],
    ];
    let mut mapped = [[0.; 2]; 4];
    let denominators = corners.map(|p| m[6] * p[0] + m[7] * p[1] + m[8]);
    if !(denominators.iter().all(|w| *w > 1e-12) || denominators.iter().all(|w| *w < -1e-12)) {
        return false;
    }
    for (i, p) in corners.into_iter().enumerate() {
        let Some(point) = project(m, p) else {
            return false;
        };
        mapped[i] = point;
    }
    valid_quad(&mapped, r.source_width, r.source_height)
}
