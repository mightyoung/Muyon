//! Original synthetic regression inputs; pending execution when Rust is available.
//! This file deliberately uses only the existing public Rust engine interface.
use muyon_office::{Limits, OfficeError, Package};
use std::io::{Cursor, Write};
use zip::{write::SimpleFileOptions, CompressionMethod, ZipWriter};

const W: &str = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
const S: &str = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";

fn archive(parts: &[(&str, &[u8])]) -> Vec<u8> {
    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, bytes) in parts {
        zip.start_file(
            *name,
            SimpleFileOptions::default().compression_method(CompressionMethod::Deflated),
        )
        .unwrap();
        zip.write_all(bytes).unwrap();
    }
    zip.finish().unwrap().into_inner()
}
fn document(text: &str) -> String {
    format!("<document xmlns=\"{W}\"><body><p><r><t>{text}</t></r></p></body></document>")
}
fn docx(xml: &str, extra: &[u8]) -> Vec<u8> {
    archive(&[
        ("word/document.xml", xml.as_bytes()),
        ("custom/original.bin", extra),
    ])
}
fn rejected_without_mutation(bytes: &[u8], limits: &Limits, expected: &str, replacement: &str) {
    let original = bytes.to_vec();
    let package = Package::open(bytes, limits).unwrap();
    let before_hash = package.source_sha256();
    let before_part = package.read_part("word/document.xml").unwrap();
    // An Err has no candidate/receipt; the engine performs no filesystem I/O.
    assert!(matches!(
        package.replace_docx_run_text(expected, replacement),
        Err(OfficeError::LimitExceeded(_))
    ));
    assert_eq!(bytes, original);
    assert_eq!(package.source_sha256(), before_hash);
    assert_eq!(package.read_part("word/document.xml").unwrap(), before_part);
    // A failed attempt must not leave partial in-memory state affecting a later edit.
    let candidate = package.replace_docx_run_text("x", "y").unwrap();
    let reopened = Package::open(&candidate.candidate, limits).unwrap();
    assert_eq!(reopened.extract_text().unwrap()[0].text, "y\n");
    assert_eq!(
        reopened.read_part("custom/original.bin").unwrap(),
        b"opaque"
    );
}

#[test]
fn inline_and_shared_rich_text_ignore_only_spreadsheet_phonetics_per_cell() {
    for (prefix, declaration) in [
        ("", format!("xmlns=\"{S}\"")),
        ("s:", format!("xmlns:s=\"{S}\"")),
    ] {
        let p = prefix;
        let sheet = format!(
            r#"<{p}worksheet {declaration} xmlns:x="urn:foreign"><{p}sheetData><{p}row>
<{p}c r="A1" t="inlineStr"><{p}is><{p}r><{p}t>漢</{p}t></{p}r><{p}rPh sb="0" eb="1"><{p}t>かん</{p}t></{p}rPh><{p}r><{p}t>字</{p}t></{p}r><{p}rPh/><x:t>ignored</x:t></{p}is></{p}c>
<{p}c r="B1" t="s"><{p}v>0</{p}v></{p}c>
<{p}c r="C1" t="inlineStr"><{p}is><{p}t>next</{p}t><x:rPh><{p}t>kept</{p}t></x:rPh></{p}is></{p}c>
<{p}c r="D1"><{p}v>7</{p}v></{p}c></{p}row></{p}sheetData></{p}worksheet>"#
        );
        let shared = format!(
            r#"<{p}sst {declaration} xmlns:x="urn:foreign"><{p}si><{p}r><{p}t>共</{p}t></{p}r><{p}rPh><{p}t>きょう</{p}t></{p}rPh><{p}r><{p}t>有</{p}t></{p}r><x:t>ignored</x:t></{p}si><{p}si><{p}t>unused</{p}t></{p}si></{p}sst>"#
        );
        let workbook = format!("<{p}workbook {declaration}/>");
        let bytes = archive(&[
            ("xl/workbook.xml", workbook.as_bytes()),
            ("xl/worksheets/sheet1.xml", sheet.as_bytes()),
            ("xl/sharedStrings.xml", shared.as_bytes()),
        ]);
        let sections = Package::open(&bytes, &Limits::default())
            .unwrap()
            .extract_text()
            .unwrap();
        assert_eq!(
            sections[0].text,
            "A1: 漢字\nB1: 共有\nC1: nextkept\nD1: 7\n"
        );
    }
}

#[test]
fn docx_input_and_total_text_boundaries_are_not_delayed_until_readback() {
    let bytes = docx(&document("x"), b"opaque");
    let limits = Limits {
        max_text: 7,
        ..Limits::default()
    };
    let package = Package::open(&bytes, &limits).unwrap();
    let equal = package.replace_docx_run_text("x", "123456").unwrap();
    assert_eq!(
        Package::open(&equal.candidate, &limits)
            .unwrap()
            .extract_text()
            .unwrap()[0]
            .text
            .len(),
        7
    );
    rejected_without_mutation(&bytes, &limits, "x", "1234567");
    rejected_without_mutation(&bytes, &limits, "x", "12345678");
    rejected_without_mutation(&bytes, &limits, "notfound", "y");
}

#[test]
fn docx_part_limit_accounts_for_escaped_bytes_before_splice() {
    let xml = document("x");
    let bytes = docx(&xml, b"opaque");
    let limits = Limits {
        max_part: xml.len() + 4,
        ..Limits::default()
    };
    let package = Package::open(&bytes, &limits).unwrap();
    // '&' occupies five XML bytes; equality is allowed.
    let equal = package.replace_docx_run_text("x", "&").unwrap();
    let reopened = Package::open(&equal.candidate, &limits).unwrap();
    assert_eq!(
        reopened.read_part("word/document.xml").unwrap().len(),
        limits.max_part
    );
    assert_eq!(reopened.extract_text().unwrap()[0].text, "&\n");
    rejected_without_mutation(&bytes, &limits, "x", "&&");
}

#[test]
fn docx_expanded_limit_counts_unchanged_parts() {
    let xml = document("x");
    let bytes = docx(&xml, b"opaque");
    let limits = Limits {
        max_expanded: xml.len() + 6 + 3,
        ..Limits::default()
    };
    let package = Package::open(&bytes, &limits).unwrap();
    let equal = package.replace_docx_run_text("x", "1234").unwrap();
    Package::open(&equal.candidate, &limits)
        .unwrap()
        .extract_text()
        .unwrap();
    rejected_without_mutation(&bytes, &limits, "x", "12345");
}

#[test]
fn highly_compressible_replacement_cannot_hide_expanded_or_part_overflow() {
    let xml = document("x");
    let bytes = docx(&xml, b"opaque");
    let limits = Limits {
        max_part: xml.len() + 10,
        max_expanded: xml.len() + 100,
        ..Limits::default()
    };
    rejected_without_mutation(&bytes, &limits, "x", &"a".repeat(100_000));
}

#[test]
fn direct_rewrite_obeys_part_and_expanded_limits_and_keeps_source() {
    let xml = document("x");
    let bytes = docx(&xml, b"opaque");
    for limits in [
        Limits {
            max_part: xml.len(),
            ..Limits::default()
        },
        Limits {
            max_expanded: xml.len() + 6,
            ..Limits::default()
        },
    ] {
        let package = Package::open(&bytes, &limits).unwrap();
        let equal = package
            .rewrite_part("word/document.xml", xml.as_bytes(), (0, 0))
            .unwrap();
        Package::open(&equal.candidate, &limits)
            .unwrap()
            .read_part("word/document.xml")
            .unwrap();
        let larger = document("xx");
        assert!(matches!(
            package.rewrite_part("word/document.xml", larger.as_bytes(), (0, 0)),
            Err(OfficeError::LimitExceeded(_))
        ));
        assert_eq!(
            package.read_part("word/document.xml").unwrap(),
            xml.as_bytes()
        );
    }
}

#[test]
fn docx_multibyte_and_archive_equal_and_one_over_are_bounded() {
    let xml = document("x");
    let bytes = docx(&xml, b"opaque");
    let text_limits = Limits {
        max_text: 7,
        ..Limits::default()
    };
    let package = Package::open(&bytes, &text_limits).unwrap();
    let equal = package.replace_docx_run_text("x", "汉字").unwrap();
    assert_eq!(
        Package::open(&equal.candidate, &text_limits)
            .unwrap()
            .extract_text()
            .unwrap()[0]
            .text
            .len(),
        7
    );
    rejected_without_mutation(&bytes, &text_limits, "x", "汉字a");
    let replacement: String = (0..128).map(|n| format!("{n:02x}")).collect();
    let candidate = Package::open(&bytes, &Limits::default())
        .unwrap()
        .replace_docx_run_text("x", &replacement)
        .unwrap();
    assert!(candidate.candidate.len() > bytes.len());
    let equal_limits = Limits {
        max_archive: candidate.candidate.len(),
        ..Limits::default()
    };
    Package::open(&bytes, &equal_limits)
        .unwrap()
        .replace_docx_run_text("x", &replacement)
        .unwrap();
    let over_limits = Limits {
        max_archive: candidate.candidate.len() - 1,
        ..Limits::default()
    };
    rejected_without_mutation(&bytes, &over_limits, "x", &replacement);
}

#[test]
fn xlsx_numeric_replacement_cannot_bypass_shared_part_budget() {
    let workbook = format!(
        r#"<workbook xmlns="{S}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Original" r:id="r1"/></sheets></workbook>"#
    );
    let rels = br#"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#;
    let sheet = format!(r#"<worksheet xmlns="{S}"><!--{}--><sheetData><row r="1"><c r="A1"><v>2</v></c></row></sheetData></worksheet>"#, "padding".repeat(100)).into_bytes();
    let bytes = archive(&[
        ("xl/workbook.xml", workbook.as_bytes()),
        ("xl/_rels/workbook.xml.rels", rels),
        ("xl/worksheets/sheet1.xml", &sheet),
    ]);
    let limits = Limits {
        max_part: sheet.len() + 3,
        ..Limits::default()
    };
    let package = Package::open(&bytes, &limits).unwrap();
    let equal = package
        .set_xlsx_numeric_cell("Original", "A1", "2", "1234")
        .unwrap();
    assert_eq!(
        Package::open(&equal.candidate, &limits)
            .unwrap()
            .read_part("xl/worksheets/sheet1.xml")
            .unwrap()
            .len(),
        limits.max_part
    );
    assert!(matches!(
        package.set_xlsx_numeric_cell("Original", "A1", "2", "12345"),
        Err(OfficeError::LimitExceeded(_))
    ));
    assert_eq!(
        package.read_part("xl/worksheets/sheet1.xml").unwrap(),
        sheet
    );
}

#[test]
fn replacement_view_uses_reader_text_budget_including_shared_references() {
    let bytes = docx(&document("x"), b"opaque");
    let limits = Limits {
        max_text: 7,
        ..Limits::default()
    };
    let package = Package::open(&bytes, &limits).unwrap();
    assert_eq!(
        package.replace_docx_run_text("1234567", "y").unwrap_err(),
        OfficeError::NotFound
    );
    assert!(matches!(
        package.rewrite_part("word/document.xml", document("1234567").as_bytes(), (0, 0)),
        Err(OfficeError::LimitExceeded(_))
    ));
}

#[test]
fn empty_text_placeholder_obeys_the_same_reader_budget() {
    let empty = docx(&document(""), b"opaque");
    let tiny = Limits {
        max_text: 1,
        ..Limits::default()
    };
    assert!(matches!(
        Package::open(&empty, &tiny).unwrap().extract_text(),
        Err(OfficeError::LimitExceeded(_))
    ));
}

#[test]
fn shared_string_rewrite_counts_every_cell_reference() {
    let workbook = format!("<workbook xmlns=\"{S}\"/>");
    let sheet = format!(
        r#"<worksheet xmlns="{S}"><sheetData><row><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>0</v></c></row></sheetData></worksheet>"#
    );
    let strings = format!("<sst xmlns=\"{S}\"><si><t>x</t></si></sst>");
    let bytes = archive(&[
        ("xl/workbook.xml", workbook.as_bytes()),
        ("xl/worksheets/sheet1.xml", sheet.as_bytes()),
        ("xl/sharedStrings.xml", strings.as_bytes()),
    ]);
    let limits = Limits {
        max_text: 12,
        ..Limits::default()
    };
    let package = Package::open(&bytes, &limits).unwrap();
    assert_eq!(package.extract_text().unwrap()[0].text.len(), 12);
    let larger = strings.replace(">x<", ">yy<");
    assert!(matches!(
        package.rewrite_part("xl/sharedStrings.xml", larger.as_bytes(), (0, 0)),
        Err(OfficeError::LimitExceeded(_))
    ));
    assert_eq!(
        package.read_part("xl/sharedStrings.xml").unwrap(),
        strings.as_bytes()
    );
}

#[test]
fn expanded_budget_counts_payload_even_on_directory_named_entries() {
    let payload = vec![b'x'; 128];
    let bytes = archive(&[("custom/", &payload)]);
    let equal = Limits {
        max_expanded: 128,
        ..Limits::default()
    };
    Package::open(&bytes, &equal).unwrap();
    let over = Limits {
        max_expanded: 127,
        ..Limits::default()
    };
    assert!(matches!(
        Package::open(&bytes, &over),
        Err(OfficeError::LimitExceeded(_))
    ));
}
