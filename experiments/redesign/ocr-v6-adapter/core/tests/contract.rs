use muyon_ocr_v6_contract::*;
use std::cell::Cell;

struct Authority(Cell<bool>);
impl SourceAuthority for Authority {
    fn allows_ocr(&self, _: &Request) -> bool {
        self.0.get()
    }
}
#[derive(Default)]
struct Store {
    pages: Vec<ValidatedPage>,
    allow: bool,
}
impl ResultStore for Store {
    fn commit_if_current(&mut self, _: &Request, page: &ValidatedPage) -> Result<(), Error> {
        if !self.allow {
            return Err(Error::SourceUnavailable);
        }
        self.pages.push(page.clone());
        Ok(())
    }
}
fn request() -> Request {
    Request {
        job_id: "job-1".into(),
        document: DocumentRef {
            scope: "local:test".into(),
            document_id: "doc-1".into(),
            revision: 7,
            source_digest: "a".repeat(64),
            blob_ref: "opaque-blob-1".into(),
        },
        raster: RasterRef {
            digest: "b".repeat(64),
            page_index: 0,
            width: 200,
            height: 100,
            exif_orientation: 1,
            source_width: 100.,
            source_height: 50.,
            coordinate_space: CoordinateSpace::PdfPoints,
            raster_to_source: [0.5, 0., 0., 0., 0.5, 0., 0., 0., 1.],
        },
        model_version: TINY_VERSION.into(),
        parameters_version: PARAMETERS_VERSION.into(),
        expires_at_ms: 1000,
    }
}
fn result(r: &Request) -> PlatformPage {
    PlatformPage {
        job_id: r.job_id.clone(),
        raster_digest: r.raster.digest.clone(),
        model_version: r.model_version.clone(),
        parameters_version: r.parameters_version.clone(),
        width: r.raster.width,
        height: r.raster.height,
        lines: vec![Line {
            text: "合计 123.45".into(),
            quad: [[20., 10.], [180., 10.], [180., 40.], [20., 40.]],
            recognition_confidence: 0.95,
            detection_confidence: None,
        }],
    }
}
fn start() -> (Task, Request, Authority, Store) {
    let r = request();
    let a = Authority(Cell::new(true));
    let t = Task::begin(r.clone(), 0, &a).unwrap();
    (
        t,
        r,
        a,
        Store {
            allow: true,
            ..Store::default()
        },
    )
}
#[test]
fn maps_to_source_coordinates_and_preserves_provenance() {
    let (mut t, r, a, mut s) = start();
    t.accept(result(&r), 10, &a, &mut s).unwrap();
    let p = &s.pages[0];
    assert_eq!(p.request, r);
    assert_eq!(p.lines[0].quad[0], [10., 5.]);
    assert_eq!(p.lines[0].text, "合计 123.45");
    assert_eq!(p.lines[0].detection_confidence, None);
    assert_eq!(t.state(), State::Completed);
    assert_eq!(t.accept(result(&r), 11, &a, &mut s), Err(Error::Terminal));
    assert_eq!(s.pages.len(), 1);
}
#[test]
fn cancelled_or_expired_result_cannot_persist() {
    for cancel in [true, false] {
        let (mut t, r, a, mut s) = start();
        if cancel {
            t.cancel();
        }
        assert_eq!(
            t.accept(result(&r), 1000, &a, &mut s),
            Err(if cancel {
                Error::Terminal
            } else {
                Error::Timeout
            })
        );
        assert!(s.pages.is_empty());
    }
}
#[test]
fn revoked_source_and_atomic_commit_failure_are_not_success() {
    let (mut t, r, a, mut s) = start();
    a.0.set(false);
    assert_eq!(
        t.accept(result(&r), 1, &a, &mut s),
        Err(Error::SourceUnavailable)
    );
    assert!(s.pages.is_empty());
    let (mut t, r, a, mut s) = start();
    s.allow = false;
    assert_eq!(
        t.accept(result(&r), 1, &a, &mut s),
        Err(Error::SourceUnavailable)
    );
    assert_ne!(t.state(), State::Completed);
}
#[test]
fn rejects_model_digest_geometry_and_confidence_mismatches() {
    for case in 0..12 {
        let (mut t, r, a, mut s) = start();
        let mut p = result(&r);
        match case {
            0 => p.model_version = "PP-OCRv5".into(),
            1 => p.raster_digest = "c".repeat(64),
            2 => p.job_id = "other".into(),
            3 => p.width = 201,
            4 => p.parameters_version = "other".into(),
            5 => p.lines[0].quad[0][0] = f64::NAN,
            6 => p.lines[0].quad[0][0] = -1.,
            7 => p.lines[0].recognition_confidence = 1.1,
            8 => p.lines[0].detection_confidence = Some(f64::NAN),
            9 => p.lines[0].quad = [[0., 0.]; 4],
            10 => p.lines[0].quad = [[0., 0.], [10., 10.], [0., 10.], [10., 0.]],
            _ => p.lines[0].text = "x".repeat(65537),
        }
        assert_eq!(
            t.accept(p, 1, &a, &mut s),
            Err(Error::InvalidResult),
            "case {case}"
        );
        assert!(s.pages.is_empty());
    }
}
#[test]
fn validates_source_transform_budgets_and_authorization_before_dispatch() {
    for case in 0..10 {
        let mut r = request();
        let a = Authority(Cell::new(case != 0));
        match case {
            1 => r.document.source_digest = "bad".into(),
            2 => r.raster.width = 0,
            3 => r.raster.raster_to_source = [0.; 9],
            4 => r.raster.exif_orientation = 9,
            5 => r.expires_at_ms = 0,
            6 => r.model_version = "PP-OCRv5".into(),
            7 => r.raster.width = 100000,
            8 => r.document.scope.clear(),
            9 => r.raster.source_width = f64::INFINITY,
            _ => {}
        }
        assert!(Task::begin(r, 0, &a).is_err(), "case {case}");
    }
}
#[test]
fn empty_page_is_a_valid_extraction_but_bad_transform_is_not() {
    let (mut t, r, a, mut s) = start();
    let mut p = result(&r);
    p.lines.clear();
    t.accept(p, 1, &a, &mut s).unwrap();
    assert!(s.pages[0].lines.is_empty());
    let mut r = request();
    r.raster.raster_to_source = [1., 0., 500., 0., 1., 0., 0., 0., 1.];
    assert!(Task::begin(r, 0, &a).is_err());
}
#[test]
fn wire_roundtrip_rejects_unknown_fields() {
    let r = request();
    let json = serde_json::to_string(&r).unwrap();
    assert_eq!(serde_json::from_str::<Request>(&json).unwrap(), r);
    let bad = json.replacen('{', "{\"extra\":true,", 1);
    assert!(serde_json::from_str::<Request>(&bad).is_err());
}
#[test]
fn accepts_shared_kotlin_wire_fixture() {
    let r: Request = serde_json::from_str(include_str!("../../fixtures/request.json")).unwrap();
    let p: PlatformPage =
        serde_json::from_str(include_str!("../../fixtures/platform-page.json")).unwrap();
    let a = Authority(Cell::new(true));
    let mut s = Store {
        allow: true,
        ..Store::default()
    };
    let mut task = Task::begin(r, 0, &a).unwrap();
    task.accept(p, 1, &a, &mut s).unwrap();
    assert_eq!(s.pages[0].lines[0].quad[0], [10., 5.]);
}

#[test]
fn rotated_raster_maps_to_physical_pdf_page_without_losing_exif_metadata() {
    let mut r = request();
    r.raster.page_index = 3;
    r.raster.exif_orientation = 6;
    r.raster.source_width = 50.;
    r.raster.source_height = 100.;
    r.raster.raster_to_source = [0., -0.5, 50., 0.5, 0., 0., 0., 0., 1.];
    let a = Authority(Cell::new(true));
    let mut s = Store {
        allow: true,
        ..Store::default()
    };
    let mut task = Task::begin(r.clone(), 0, &a).unwrap();
    task.accept(result(&r), 1, &a, &mut s).unwrap();
    assert_eq!(s.pages[0].lines[0].quad[0], [45., 10.]);
    assert_eq!(s.pages[0].request.raster.page_index, 3);
    assert_eq!(s.pages[0].request.raster.exif_orientation, 6);
}
