//! Fidelity and safety tests against the repository's synthetic fixtures.
//! Pre-declared operations come from tools/document_fidelity manifests:
//! DOCX run "target" -> "edited" (unique), XLSX Original!A1 "2" -> "5".

use muyon_office::{Limits, OfficeError, Package};
use std::io::{Cursor, Read, Write};
use zip::{write::SimpleFileOptions, CompressionMethod, ZipArchive, ZipWriter};

fn fixture(rel: &str) -> Vec<u8> {
    let p = format!(
        "{}/../../tools/document_fidelity/{rel}",
        env!("CARGO_MANIFEST_DIR")
    );
    std::fs::read(&p).unwrap_or_else(|e| panic!("fixture {p}: {e}"))
}
fn open(bytes: &[u8]) -> Package {
    Package::open(bytes, &Limits::default()).unwrap()
}
/// (name, raw compressed bytes, decompressed bytes) per member, in archive order.
fn members(bytes: &[u8]) -> Vec<(String, Vec<u8>, Vec<u8>)> {
    let mut a = ZipArchive::new(Cursor::new(bytes)).unwrap();
    (0..a.len())
        .map(|i| {
            let mut raw = Vec::new();
            a.by_index_raw(i).unwrap().read_to_end(&mut raw).unwrap();
            let mut f = a.by_index(i).unwrap();
            let name = f.name().unwrap().into_owned();
            let mut plain = Vec::new();
            f.read_to_end(&mut plain).unwrap();
            (name, raw, plain)
        })
        .collect()
}
/// Exactly one member changed, order preserved, other members identical raw AND decompressed,
/// and the changed member equals source with only `range` replaced by `new_text`.
fn assert_single_splice(src: &[u8], receipt: &muyon_office::EditReceipt, new_text: &str) {
    let before = members(src);
    let after = members(&receipt.candidate);
    assert_eq!(before.len(), after.len());
    let mut changed = 0;
    for (b, a) in before.iter().zip(after.iter()) {
        assert_eq!(b.0, a.0, "order/name preserved");
        if b.0 == receipt.changed_part {
            changed += 1;
            let (s, e) = receipt.changed_range;
            let mut expect = b.2[..s].to_vec();
            expect.extend_from_slice(new_text.as_bytes());
            expect.extend_from_slice(&b.2[e..]);
            assert_eq!(a.2, expect, "only the declared range changed");
        } else {
            assert_eq!(
                b.1, a.1,
                "raw compressed bytes of {} must be identical",
                b.0
            );
            assert_eq!(b.2, a.2, "content of {} must be identical", b.0);
        }
    }
    assert_eq!(changed, 1);
    assert_eq!(
        receipt.source_sha256,
        muyon_office::Package::open(src, &Limits::default())
            .unwrap()
            .source_sha256()
    );
}

#[test]
fn docx_simple_run_edit_changes_only_the_target_text() {
    let src = fixture("fixtures_subsets/simple-run.docx");
    let r = open(&src)
        .replace_docx_run_text("target", "edited")
        .unwrap();
    assert_single_splice(&src, &r, "edited");
    let text = open(&r.candidate).extract_text().unwrap();
    assert_eq!(text[0].text, "Original edited unchanged\n");
}

#[test]
fn docx_complex_edit_keeps_bookmarks_comments_header_and_unknown_part() {
    let src = fixture("fixtures_complex/complex.docx");
    let r = open(&src)
        .replace_docx_run_text("target", "edited")
        .unwrap();
    assert_single_splice(&src, &r, "edited");
    let after = members(&r.candidate);
    let doc = String::from_utf8(
        after
            .iter()
            .find(|m| m.0 == "word/document.xml")
            .unwrap()
            .2
            .clone(),
    )
    .unwrap();
    for needle in [
        r#"<bookmarkStart w:id="1" w:name="SyntheticTarget"/>"#,
        r#"<commentRangeStart w:id="0"/>"#,
        "<rPr><b/></rPr><t>edited</t>",
        r#"<commentReference w:id="0"/>"#,
        r#"<headerReference w:type="default" r:id="rId3"/>"#,
    ] {
        assert!(doc.contains(needle), "{needle}");
    }
    assert!(
        after.iter().any(|m| m.0 == "custom/original.bin"),
        "opaque part kept"
    );
}

#[test]
fn docx_edit_is_deterministic_and_reopens() {
    let src = fixture("fixtures_complex/complex.docx");
    let a = open(&src)
        .replace_docx_run_text("target", "edited")
        .unwrap();
    let b = open(&src)
        .replace_docx_run_text("target", "edited")
        .unwrap();
    assert_eq!(a.candidate, b.candidate);
    assert_eq!(a.candidate_sha256, b.candidate_sha256);
    open(&a.candidate);
}

#[test]
fn docx_not_found_and_ambiguous_never_guess() {
    let src = fixture("fixtures_subsets/simple-run.docx");
    assert_eq!(
        open(&src)
            .replace_docx_run_text("missing", "x")
            .unwrap_err(),
        OfficeError::NotFound
    );
    // "Original " and " unchanged" each unique; build an ambiguous one.
    let amb = build_docx(r#"<t>same</t></r><r><t>same</t>"#);
    assert_eq!(
        open(&amb).replace_docx_run_text("same", "x").unwrap_err(),
        OfficeError::Ambiguous
    );
}

#[test]
fn docx_replacement_rules() {
    let src = fixture("fixtures_subsets/simple-run.docx");
    let p = open(&src);
    assert!(matches!(
        p.replace_docx_run_text("target", ""),
        Err(OfficeError::InvalidReplacement(_))
    ));
    assert!(matches!(
        p.replace_docx_run_text("target", "a\u{0}b"),
        Err(OfficeError::InvalidReplacement(_))
    ));
    // Whitespace at the edges needs xml:space="preserve" on that run; "target" has none.
    assert!(matches!(
        p.replace_docx_run_text("target", " x"),
        Err(OfficeError::InvalidReplacement(_))
    ));
    // Escaping: markup characters are text, never markup.
    let r = p.replace_docx_run_text("target", "a<b>&c").unwrap();
    assert_eq!(
        open(&r.candidate).extract_text().unwrap()[0].text,
        "Original a<b>&c unchanged\n"
    );
    // A run that already preserves space may carry edge whitespace.
    let r2 = p.replace_docx_run_text("Original ", "  Hi ").unwrap();
    assert_single_splice(&src, &r2, "  Hi ");
}

#[test]
fn xlsx_numeric_cell_edit_keeps_formula_cache_and_everything_else() {
    let src = fixture("fixtures/minimal.xlsx");
    let r = open(&src)
        .set_xlsx_numeric_cell("Original", "A1", "2", "5")
        .unwrap();
    assert_single_splice(&src, &r, "5");
    let sheet = String::from_utf8(
        members(&r.candidate)
            .into_iter()
            .find(|m| m.0 == "xl/worksheets/sheet1.xml")
            .unwrap()
            .2,
    )
    .unwrap();
    // Dependent formula cache is deliberately NOT recalculated.
    assert!(sheet.contains("<c r=\"B1\"><f>A1+1</f><v>3</v></c>"));
    assert!(sheet.contains("<c r=\"A1\"><v>5</v></c>"));
}

#[test]
fn xlsx_complex_edit_preserves_merge_comment_hidden_sheet_and_date_system() {
    let src = fixture("fixtures_complex/complex.xlsx");
    let r = open(&src)
        .set_xlsx_numeric_cell("Original", "A1", "2", "5")
        .unwrap();
    assert_single_splice(&src, &r, "5");
    let m = members(&r.candidate);
    let wb = String::from_utf8(
        m.iter()
            .find(|x| x.0 == "xl/workbook.xml")
            .unwrap()
            .2
            .clone(),
    )
    .unwrap();
    assert!(wb.contains(r#"date1904="1""#) && wb.contains(r#"state="hidden""#));
    assert!(m.iter().any(|x| x.0 == "xl/comments/comment1.xml"));
}

#[test]
fn xlsx_refuses_what_it_cannot_prove() {
    let src = fixture("fixtures_complex/complex.xlsx");
    let p = open(&src);
    // formula cell, inline-string cell, date cell with different expected, hidden sheet, wrong sheet
    assert!(matches!(
        p.set_xlsx_numeric_cell("Original", "B1", "999", "1"),
        Err(OfficeError::Unsupported(_))
    ));
    assert!(matches!(
        p.set_xlsx_numeric_cell("Original", "A3", "1", "2"),
        Err(OfficeError::Unsupported(_))
    ));
    assert_eq!(
        p.set_xlsx_numeric_cell("Original", "A1", "3", "5")
            .unwrap_err(),
        OfficeError::NotFound
    );
    assert!(matches!(
        p.set_xlsx_numeric_cell("Hidden", "A1", "1", "2"),
        Err(OfficeError::Unsupported(_))
    ));
    assert_eq!(
        p.set_xlsx_numeric_cell("Nope", "A1", "2", "5").unwrap_err(),
        OfficeError::NotFound
    );
    assert!(matches!(
        p.set_xlsx_numeric_cell("Original", "A1", "2", "NaN"),
        Err(OfficeError::InvalidReplacement(_))
    ));
    assert!(matches!(
        p.set_xlsx_numeric_cell("Original", "a1", "2", "5"),
        Err(OfficeError::InvalidReplacement(_))
    ));
}

#[test]
fn extract_text_covers_docx_xlsx_and_flags_formula_cache() {
    let d = open(&fixture("fixtures_complex/complex.docx"))
        .extract_text()
        .unwrap();
    assert_eq!(d[0].text, "Original target unchanged\n");
    let x = open(&fixture("fixtures_complex/complex.xlsx"))
        .extract_text()
        .unwrap();
    assert!(x[0].text.contains("B1: 999 [公式缓存值]"));
    assert!(x[0].text.contains("A3: Original merged title"));
}

fn zip_of(entries: &[(&str, Vec<u8>)]) -> Vec<u8> {
    let mut w = ZipWriter::new(Cursor::new(Vec::new()));
    for (n, c) in entries {
        w.start_file(
            *n,
            SimpleFileOptions::default().compression_method(CompressionMethod::Deflated),
        )
        .unwrap();
        w.write_all(c).unwrap();
    }
    w.finish().unwrap().into_inner()
}
fn build_docx(body_runs: &str) -> Vec<u8> {
    let xml = format!(
        r#"<document xmlns="{}"><body><p><r>{}</r></p></body></document>"#,
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main", body_runs
    );
    zip_of(&[("word/document.xml", xml.into_bytes())])
}

#[test]
fn hostile_packages_are_rejected() {
    // zip-slip style names
    assert_eq!(
        Package::open(
            &zip_of(&[("../evil.xml", b"x".to_vec())]),
            &Limits::default()
        )
        .err(),
        Some(OfficeError::UnsafePath)
    );
    assert_eq!(
        Package::open(&zip_of(&[("/abs.xml", b"x".to_vec())]), &Limits::default()).err(),
        Some(OfficeError::UnsafePath)
    );
    // not a zip
    assert_eq!(
        Package::open(b"PK nope", &Limits::default()).err(),
        Some(OfficeError::MalformedArchive)
    );
    // expansion bomb: tiny compressed, huge expanded
    let bomb = zip_of(&[("word/document.xml", vec![b'a'; 40 * 1024 * 1024])]);
    assert!(bomb.len() < 1024 * 1024);
    assert_eq!(
        Package::open(&bomb, &Limits::default()).err(),
        Some(OfficeError::LimitExceeded("expanded size"))
    );
    // entry count
    let many: Vec<(String, Vec<u8>)> = (0..1030)
        .map(|i| (format!("p{i}.xml"), vec![b'x']))
        .collect();
    let refs: Vec<(&str, Vec<u8>)> = many.iter().map(|(n, c)| (n.as_str(), c.clone())).collect();
    assert_eq!(
        Package::open(&zip_of(&refs), &Limits::default()).err(),
        Some(OfficeError::LimitExceeded("entry count"))
    );
}

#[test]
fn hostile_xml_is_rejected_not_expanded() {
    let ns = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
    let mk = |inner: &str| {
        zip_of(&[(
            "word/document.xml",
            format!(
                "{inner}<document xmlns=\"{ns}\"><body><p><r><t>x</t></r></p></body></document>"
            )
            .into_bytes(),
        )])
    };
    let dtd = mk(r#"<!DOCTYPE d [<!ENTITY e SYSTEM "file:///etc/passwd">]>"#);
    assert_eq!(
        open(&dtd).replace_docx_run_text("x", "y").unwrap_err(),
        OfficeError::DtdNotAllowed
    );
    let ent = zip_of(&[(
        "word/document.xml",
        format!("<document xmlns=\"{ns}\"><body><p><r><t>&xxe;</t></r></p></body></document>")
            .into_bytes(),
    )]);
    assert_eq!(
        open(&ent).replace_docx_run_text("x", "y").unwrap_err(),
        OfficeError::UnsupportedEntity
    );
    // depth bomb
    let deep = format!(
        "<document xmlns=\"{ns}\">{}{}</document>",
        "<a>".repeat(200),
        "</a>".repeat(200)
    );
    let d = zip_of(&[("word/document.xml", deep.into_bytes())]);
    assert_eq!(
        open(&d).replace_docx_run_text("x", "y").unwrap_err(),
        OfficeError::LimitExceeded("xml depth")
    );
    // malformed
    let bad = zip_of(&[(
        "word/document.xml",
        format!("<document xmlns=\"{ns}\"><body></document>").into_bytes(),
    )]);
    assert!(matches!(
        open(&bad).replace_docx_run_text("x", "y"),
        Err(OfficeError::MalformedXml(_))
    ));
}

#[test]
fn wrong_format_is_unsupported() {
    let x = open(&fixture("fixtures/minimal.xlsx"));
    assert_eq!(
        x.replace_docx_run_text("a", "b").unwrap_err(),
        OfficeError::UnsupportedFormat
    );
    let d = open(&fixture("fixtures_subsets/simple-run.docx"));
    assert_eq!(
        d.set_xlsx_numeric_cell("S", "A1", "1", "2").unwrap_err(),
        OfficeError::UnsupportedFormat
    );
}
