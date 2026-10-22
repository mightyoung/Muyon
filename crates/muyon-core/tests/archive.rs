use muyon_core::archive::{parse_archive, DecodedEntryValidator};
use muyon_core::contract::{ArchiveMethod, ContractError};

const STORED: &[u8] = include_bytes!("fixtures/archive/stored.zip");
const DEFLATED: &[u8] = include_bytes!("fixtures/archive/deflated.zip");
const DESCRIPTOR: &[u8] = include_bytes!("fixtures/archive/descriptor.zip");
fn pos(bytes: &[u8], signature: &[u8]) -> usize {
    bytes
        .windows(signature.len())
        .position(|w| w == signature)
        .unwrap()
}
fn put16(bytes: &mut [u8], at: usize, value: u16) {
    bytes[at..at + 2].copy_from_slice(&value.to_le_bytes());
}
fn put32(bytes: &mut [u8], at: usize, value: u32) {
    bytes[at..at + 4].copy_from_slice(&value.to_le_bytes());
}

#[test]
fn stored_deflated_and_signed_descriptor_metadata() {
    for bytes in [STORED, DEFLATED, DESCRIPTOR] {
        let manifest = parse_archive(bytes).unwrap();
        assert_eq!(manifest.archive_length, bytes.len() as u64);
        assert_eq!(manifest.entries.len(), 1);
        let entry = &manifest.entries[0];
        assert_eq!(entry.name, "论文/测试.json");
        assert_eq!(entry.expanded_length, 18);
        assert_eq!(
            entry.method,
            if bytes == STORED {
                ArchiveMethod::Stored
            } else {
                ArchiveMethod::Deflated
            }
        );
        let mut validator = DecodedEntryValidator::new(entry);
        validator.update(b"{\"title\":").unwrap();
        validator.update(b"\"sample\"}").unwrap();
        validator.finish().unwrap();
    }
}
#[test]
fn accepts_unsigned_descriptor() {
    let mut bytes = DESCRIPTOR.to_vec();
    let descriptor = pos(&bytes, b"PK\x07\x08");
    bytes.drain(descriptor..descriptor + 4);
    let eocd = pos(&bytes, b"PK\x05\x06");
    let central = pos(&bytes, b"PK\x01\x02");
    put32(&mut bytes, eocd + 16, central as u32);
    assert!(parse_archive(&bytes).is_ok());
}
#[test]
fn directories_validated_but_not_exposed() {
    let m = parse_archive(include_bytes!("fixtures/archive/directories.zip")).unwrap();
    assert_eq!(m.entries.len(), 1);
    assert_eq!(m.entries[0].name, "a/b.json");
}

#[test]
fn actual_archive409_encoder_round_trip_fixture() {
    let bytes = include_bytes!("fixtures/archive/archive409.zip");
    let manifest = parse_archive(bytes).unwrap();
    assert_eq!(manifest.entries.len(), 3);
    assert!(manifest.entries.iter().any(|e| e.name == "论文/测试.json"));
    for entry in &manifest.entries {
        let content: &[u8] = match entry.name.as_str() {
            "manifest.json" => b"{\"packageType\":\"muyon-research\",\"schemaVersion\":1}",
            "project.json" => b"{\"originProjectKey\":\"p\"}",
            "论文/测试.json" => b"{\"title\":\"sample\"}",
            other => panic!("unexpected {other}"),
        };
        let mut validator = DecodedEntryValidator::new(entry);
        validator.update(content).unwrap();
        validator.finish().unwrap();
    }
}

#[test]
fn contract_entries_bind_exact_snapshot_digest_and_length() {
    use muyon_core::contract::{BlobRef, FileSource, ReadLease, Revision};
    let manifest = parse_archive(STORED).unwrap();
    let mut source = FileSource {
        snapshot_id: "snapshot-a".into(),
        blob: BlobRef {
            digest: manifest.archive_digest.clone(),
            byte_length: Revision::new(STORED.len() as u64),
        },
        lease: ReadLease {
            lease_id: "lease-a".into(),
            owner_epoch: "epoch-a".into(),
            generation: Revision::new(1),
        },
    };
    assert_eq!(manifest.to_contract_entries(&source).unwrap().len(), 1);
    source.blob.digest = "0".repeat(64);
    assert_eq!(
        manifest.to_contract_entries(&source),
        Err(ContractError::BindingMismatch)
    );
    source.blob.digest = manifest.archive_digest.clone();
    source.blob.byte_length = Revision::new(1);
    assert_eq!(
        manifest.to_contract_entries(&source),
        Err(ContractError::BindingMismatch)
    );
}
#[test]
fn rejects_path_aliases_links_and_special_files() {
    for fixture in [
        &include_bytes!("fixtures/archive/fifo.zip")[..],
        &include_bytes!("fixtures/archive/device.zip")[..],
        &include_bytes!("fixtures/archive/absolute.zip")[..],
        &include_bytes!("fixtures/archive/backslash.zip")[..],
        &include_bytes!("fixtures/archive/drive.zip")[..],
        &include_bytes!("fixtures/archive/empty-part.zip")[..],
        &include_bytes!("fixtures/archive/duplicate.zip")[..],
        &include_bytes!("fixtures/archive/unicode-alias.zip")[..],
        &include_bytes!("fixtures/archive/prefix-file.zip")[..],
    ] {
        assert!(parse_archive(fixture).is_err());
    }
}

#[test]
fn traversal_guard() {
    assert!(parse_archive(include_bytes!("fixtures/archive/traversal.zip")).is_err());
}

#[test]
fn symlink_guard() {
    assert!(parse_archive(include_bytes!("fixtures/archive/symlink.zip")).is_err());
}

#[test]
fn overlap_guard() {
    assert!(parse_archive(include_bytes!("fixtures/archive/overlap.zip")).is_err());
}
#[test]
fn rejects_offsets_local_conflicts_flags_zip64_and_quotas() {
    let c = pos(STORED, b"PK\x01\x02");
    let e = pos(STORED, b"PK\x05\x06");
    for (at, value, width) in [
        (c + 42, 1, 4),
        (c + 42, u32::MAX, 4),
        (c + 20, u32::MAX, 4),
        (c + 24, 30 * 1024 * 1024 + 1, 4),
        (c + 8, 0x801, 2),
        (c + 8, 0x810, 2),
        (c + 10, 99, 2),
        (c + 34, 1, 2),
        (e + 4, 1, 2),
        (e + 6, 1, 2),
        (e + 10, 10001, 2),
        (e + 16, u32::MAX, 4),
        (14, 1, 4),
        (6, 0, 2),
        (8, 8, 2),
        (c + 38, 0o120777 << 16, 4),
    ] {
        let mut b = STORED.to_vec();
        if width == 2 {
            put16(&mut b, at, value as u16);
        } else {
            put32(&mut b, at, value);
        }
        assert!(
            parse_archive(&b).is_err(),
            "accepted offset {at} value {value}"
        );
    }
}
#[test]
fn all_truncations_fail_without_panicking() {
    for n in 0..DESCRIPTOR.len() {
        assert!(parse_archive(&DESCRIPTOR[..n]).is_err());
    }
}

#[test]
fn refuses_overlapping_ranges_and_unknown_extra_fields() {
    for bytes in [
        &include_bytes!("fixtures/archive/overlap.zip")[..],
        &include_bytes!("fixtures/archive/unknown-extra.zip")[..],
        &include_bytes!("fixtures/archive/zip64-extra.zip")[..],
    ] {
        assert!(parse_archive(bytes).is_err());
    }
    assert_eq!(
        parse_archive(include_bytes!("fixtures/archive/aggregate-limit.zip")),
        Err(ContractError::TextLimit)
    );
}
#[test]
fn descriptor_and_decoded_content_are_independent_checks() {
    let mut bad_descriptor = DESCRIPTOR.to_vec();
    let p = pos(&bad_descriptor, b"PK\x07\x08");
    put32(&mut bad_descriptor, p + 4, 1);
    assert!(parse_archive(&bad_descriptor).is_err());
    let m = parse_archive(STORED).unwrap();
    let entry = &m.entries[0];
    let mut corrupt = STORED.to_vec();
    corrupt[entry.data_offset as usize] ^= 1;
    // Metadata parsing intentionally cannot certify payload CRC.
    assert!(parse_archive(&corrupt).is_ok());
    let mut validator = DecodedEntryValidator::new(entry);
    validator
        .update(&corrupt[entry.data_offset as usize..entry.data_offset as usize + 18])
        .unwrap();
    assert_eq!(validator.finish(), Err(ContractError::BindingMismatch));
    let mut short = DecodedEntryValidator::new(entry);
    short.update(b"short").unwrap();
    assert!(short.finish().is_err());
    let mut long = DecodedEntryValidator::new(entry);
    assert!(long.update(&[0; 19]).is_err());
    assert!(long.finish().is_err());
}
