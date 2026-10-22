use muyon_core::contract::*;
use serde_json::{json, Value};

fn supplier() -> SupplierPayload {
    serde_json::from_value(json!({"name":"  e\u{301}  ","aliases":["乙","甲","甲"],"address":null,"categories":[],"notes":null,"merged_into":null,"rating":null,"rating_note":null})).unwrap()
}
fn envelope() -> CommandEnvelope {
    let mut command = CommandEnvelope {
        protocol_version: 1,
        business_version: 1,
        intent_id: "intent-a".into(),
        scope: Scope {
            workspace_id: "workspace-a".into(),
            project_id: None,
        },
        expected_revision: Revision::new(0),
        authority: AuthorityBinding {
            grant_id: "grant-a".into(),
            generation: Revision::new(1),
            owner_epoch: "epoch-a".into(),
        },
        plan_id: "plan-a".into(),
        plan_digest: "0".repeat(64),
        command: Operation::SupplierCreate {
            supplier_id: "supplier-a".into(),
            payload: supplier(),
        },
    };
    command.plan_digest = command.expected_plan_digest().unwrap();
    command
}
fn seal(command: &mut CommandEnvelope) {
    command.plan_digest = command.expected_plan_digest().unwrap();
}

#[test]
fn ct01_eight_fields_normalize_with_dart_rules() {
    let normalized = supplier().normalize().unwrap();
    assert_eq!(normalized.name, "é");
    assert_eq!(normalized.aliases, ["乙", "甲"]);
    assert_eq!(
        serde_json::to_value(&normalized)
            .unwrap()
            .as_object()
            .unwrap()
            .len(),
        8
    );
    let mut invalid = supplier();
    invalid.rating = Some("star".into());
    assert!(invalid.normalize().is_err());
    invalid = supplier();
    invalid.merged_into = Some("supplier-b".into());
    assert_eq!(
        invalid.normalize(),
        Err(ContractError::UnsupportedOperation)
    );
    invalid = supplier();
    invalid.categories = vec!["a".into(); 21];
    assert!(invalid.normalize().is_err());
    invalid = supplier();
    invalid.rating_note = Some("x".repeat(501));
    assert!(invalid.normalize().is_err());
}

#[test]
fn ct01_reuses_supplier_name_boundary_vectors() {
    // RD-P01 domain.rs vectors, themselves based on M02/M04/M05 Dart reference.
    for (raw, expected) in [
        ("\u{feff} e\u{301} \u{feff}", "é"),
        ("Ａ", "Ａ"),
        ("甲\t\n\r 乙\u{fffd}", "甲\t\n\r 乙\u{fffd}"),
    ] {
        assert_eq!(
            normalize_name(&raw.encode_utf16().collect::<Vec<_>>()),
            Ok(expected.into())
        );
    }
    for raw in ["", " \t\n\r\u{feff}"] {
        assert_eq!(
            normalize_name(&raw.encode_utf16().collect::<Vec<_>>()),
            Err(ContractError::Required)
        );
    }
    for raw in ["\u{b}甲", "甲\u{c}", "\u{0}甲", "\u{fffe}", "\u{ffff}"] {
        assert_eq!(
            normalize_name(&raw.encode_utf16().collect::<Vec<_>>()),
            Err(ContractError::InvalidXml)
        );
    }
    for raw in [vec![0xd800], vec![0xdc00], vec![0xd800, 0x7532]] {
        assert_eq!(normalize_name(&raw), Err(ContractError::InvalidXml));
    }
    assert_eq!(
        normalize_name(&"😀".repeat(200).encode_utf16().collect::<Vec<_>>())
            .unwrap()
            .chars()
            .count(),
        200
    );
    assert_eq!(
        normalize_name(&"😀".repeat(201).encode_utf16().collect::<Vec<_>>()),
        Err(ContractError::TextLimit)
    );
    assert_eq!(
        normalize_name(&(" ".repeat(1999) + "甲").encode_utf16().collect::<Vec<_>>()),
        Ok("甲".into())
    );
    assert_eq!(
        normalize_name(&(" ".repeat(2000) + "甲").encode_utf16().collect::<Vec<_>>()),
        Err(ContractError::RawLimit)
    );
}

#[test]
fn ct01_revisions_are_lossless_canonical_text() {
    assert!(Revision::new(10) > Revision::new(9));
    for valid in ["0", "9007199254740993", "18446744073709551615"] {
        assert_eq!(Revision::parse(valid).unwrap().as_str(), valid);
    }
    for invalid in ["", "01", "-1", "1.0", "1e3", "+1", "18446744073709551616"] {
        assert!(Revision::parse(invalid).is_err());
    }
    for invalid in ["1", "1.0", "1e3", "null", "true"] {
        assert!(serde_json::from_str::<Revision>(invalid).is_err());
    }
    assert!(Revision::new(u64::MAX).next().is_err());
}

#[test]
fn ct02_manual_paper_requires_project_title_and_blob() {
    let mut command = envelope();
    command.command = Operation::PaperCreate {
        paper_id: "paper-a".into(),
        payload: PaperPayload {
            title: "论文".into(),
            authors: vec![],
            year: None,
            doi: None,
            url: None,
            notes: None,
            attachment: BlobRef {
                digest: "a".repeat(64),
                byte_length: Revision::new(20),
            },
            attachment_upload_id: None,
        },
    };
    seal(&mut command);
    assert_eq!(command.validate(), Err(ContractError::ScopeMismatch));
    command.scope.project_id = Some("project-a".into());
    seal(&mut command);
    assert!(command.validate().is_ok());
    if let Operation::PaperCreate { payload, .. } = &mut command.command {
        payload.attachment_upload_id = Some("upload-a".into());
    }
    assert_eq!(command.validate(), Err(ContractError::BindingMismatch));
    seal(&mut command);
    assert!(command.validate().is_ok());
    if let Operation::PaperCreate { payload, .. } = &mut command.command {
        payload.title = " ".into();
    }
    seal(&mut command);
    assert_eq!(command.validate(), Err(ContractError::Required));
    if let Operation::PaperCreate { payload, .. } = &mut command.command {
        payload.title = "x".repeat(501);
    }
    seal(&mut command);
    assert_eq!(command.validate(), Err(ContractError::TextLimit));
    if let Operation::PaperCreate { payload, .. } = &mut command.command {
        payload.title = "论文".into();
        payload.attachment.byte_length = Revision::new(30 * 1024 * 1024);
    }
    seal(&mut command);
    assert!(command.validate().is_ok());
    if let Operation::PaperCreate { payload, .. } = &mut command.command {
        payload.attachment.byte_length = Revision::new(30 * 1024 * 1024 + 1);
    }
    seal(&mut command);
    assert_eq!(command.validate(), Err(ContractError::TextLimit));
}

#[test]
fn ct02_import_is_opaque_metadata_not_manual_paper() {
    let mut command = envelope();
    command.scope.project_id = Some("project-a".into());
    command.command = Operation::ResearchImport {
        source_id: "source-a".into(),
        source_revision: Revision::new(9),
        snapshot_upload_id: None,
        snapshot: BlobRef {
            digest: "a".repeat(64),
            byte_length: Revision::new(20),
        },
        records: vec![ImportedPaper {
            source_id: "source-paper-a".into(),
            source_revision: Revision::new(9007199254740993),
            record: json!({"title":null,"custom":{"score":0.25,"operation":"not-executable"}}),
            raw_json:
                "{\"title\":null,\"custom\":{\"score\":0.25,\"operation\":\"not-executable\"}}"
                    .into(),
            attachments: vec![],
            attachment_upload_ids: Default::default(),
        }],
    };
    seal(&mut command);
    let raw = serde_json::to_string(&command).unwrap();
    assert_eq!(CommandEnvelope::decode(&raw).unwrap(), command);
    let original_digest = command.binding_digest().unwrap();
    let mut changed_upload = command.clone();
    if let Operation::ResearchImport {
        snapshot_upload_id, ..
    } = &mut changed_upload.command
    {
        *snapshot_upload_id = Some("upload-snapshot-a".into());
    }
    assert_eq!(
        changed_upload.validate(),
        Err(ContractError::BindingMismatch)
    );
    seal(&mut changed_upload);
    assert_ne!(original_digest, changed_upload.binding_digest().unwrap());
    if let Operation::ResearchImport { records, .. } = &mut changed_upload.command {
        records[0]
            .attachment_upload_ids
            .insert("b".repeat(64), "upload-unrelated".into());
    }
    seal(&mut changed_upload);
    assert_eq!(
        changed_upload.validate(),
        Err(ContractError::BindingMismatch)
    );
    if let Operation::ResearchImport { records, .. } = &mut command.command {
        records[0].record["custom"]["score"] = json!(0.5);
        records[0].raw_json = records[0].record.to_string();
    }
    assert_eq!(command.validate(), Err(ContractError::BindingMismatch));
    seal(&mut command);
    assert_ne!(original_digest, command.binding_digest().unwrap());
    if let Operation::ResearchImport { records, .. } = &mut command.command {
        records[0].raw_json = "{}".into();
    }
    seal(&mut command);
    assert_eq!(command.validate(), Err(ContractError::BindingMismatch));
}

#[test]
fn ct03_every_security_fact_changes_retry_binding() {
    let command = envelope();
    let original = command.binding_digest().unwrap();
    let mut changed = command.clone();
    changed.authority.generation = Revision::new(2);
    assert_ne!(original, changed.binding_digest().unwrap());
    changed = command.clone();
    changed.authority.owner_epoch = "epoch-b".into();
    assert_ne!(original, changed.binding_digest().unwrap());
    changed = command.clone();
    changed.authority.grant_id = "grant-b".into();
    assert_ne!(original, changed.binding_digest().unwrap());
    changed = command.clone();
    changed.intent_id = "intent-b".into();
    assert_ne!(original, changed.binding_digest().unwrap());
    changed = command.clone();
    changed.scope.workspace_id = "workspace-b".into();
    assert_eq!(changed.validate(), Err(ContractError::BindingMismatch));
    changed = command.clone();
    if let Operation::SupplierCreate { payload, .. } = &mut changed.command {
        payload.name = "é".into();
    }
    assert_eq!(changed.validate(), Err(ContractError::BindingMismatch)); // raw binding differs, even same normalized text
    changed = command.clone();
    changed.authority.generation = Revision::new(0);
    assert_eq!(changed.validate(), Err(ContractError::InvalidAuthority));
}

#[test]
fn ct04_strict_decode_rejects_duplicates_unknown_and_versions() {
    let command = envelope();
    let mut value = serde_json::to_value(&command).unwrap();
    assert_eq!(
        CommandEnvelope::decode(&value.to_string()).unwrap(),
        command
    );
    value["authority"]["user_confirmed"] = json!(true);
    assert!(CommandEnvelope::decode(&value.to_string()).is_err());
    value = serde_json::to_value(&command).unwrap();
    value["protocol_version"] = json!(2);
    assert_eq!(
        CommandEnvelope::decode(&value.to_string()),
        Err(ContractError::InvalidVersion)
    );
    value = serde_json::to_value(&command).unwrap();
    value["business_version"] = json!(2);
    assert_eq!(
        CommandEnvelope::decode(&value.to_string()),
        Err(ContractError::InvalidVersion)
    );
    for raw in [
        "{\"a\":1,\"a\":2}",
        "{\"a\":{\"b\":1,\"b\":2}}",
        "{\"a\":1,\"\\u0061\":2}",
        "{}{}",
    ] {
        assert!(decode_json(raw).is_err());
    }
    let duplicate = serde_json::to_string(&command).unwrap().replacen(
        "\"intent_id\":",
        "\"intent_id\":\"forged\",\"intent_id\":",
        1,
    );
    assert_eq!(
        CommandEnvelope::decode(&duplicate),
        Err(ContractError::InvalidJson)
    );
    value = serde_json::to_value(&command).unwrap();
    value["command"]["capability"] = json!("forged");
    assert!(CommandEnvelope::decode(&value.to_string()).is_err());
    value = serde_json::to_value(&command).unwrap();
    value["expected_revision"] = json!(0.0);
    assert!(CommandEnvelope::decode(&value.to_string()).is_err());
}

#[test]
fn ct04_digest_order_and_fixture_round_trip() {
    assert_eq!(
        stable_digest(&json!({"z":1,"a":{"y":2,"x":3}})).unwrap(),
        stable_digest(&json!({"a":{"x":3,"y":2},"z":1})).unwrap()
    );
    assert_eq!(
        stable_digest(&Value::Null).unwrap(),
        "74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b"
    );
    let fixture =
        include_str!("../../../docs/contracts/muyon-android/fixtures/supplier-create.json");
    let command = CommandEnvelope::decode(fixture).unwrap();
    assert_eq!(command.binding_digest().unwrap().len(), 64);
    let lifecycle: Value = serde_json::from_str(include_str!(
        "../../../docs/contracts/muyon-android/fixtures/lifecycle.json"
    ))
    .unwrap();
    let create_receipt: Receipt =
        serde_json::from_value(lifecycle["create"]["receipt"].clone()).unwrap();
    assert!(create_receipt.validate_for(&command).is_ok());
    for action in ["delete", "restore"] {
        let command = CommandEnvelope::decode(&lifecycle[action]["command"].to_string()).unwrap();
        let receipt: Receipt =
            serde_json::from_value(lifecycle[action]["receipt"].clone()).unwrap();
        assert!(receipt.validate_for(&command).is_ok());
    }
}

#[test]
fn ct03_receipt_and_unknown_states_have_distinct_invariants() {
    let command = envelope();
    let receipt = Receipt {
        protocol_version: 1,
        intent_id: command.intent_id.clone(),
        binding_digest: command.binding_digest().unwrap(),
        scope: command.scope.clone(),
        authority: command.authority.clone(),
        admission_id: None,
        target_id: command.command.target_id().into(),
        revision: Revision::new(1),
        status: ExecutionStatus::Committed,
        result: json!({"name":"é"}),
    };
    assert!(receipt.validate_for(&command).is_ok());
    let mut wrong = receipt.clone();
    wrong.authority.generation = Revision::new(2);
    assert_eq!(
        wrong.validate_for(&command),
        Err(ContractError::BindingMismatch)
    );
    let mut result = ExecutionResult {
        status: ExecutionStatus::Committed,
        receipt: Some(receipt),
        error: None,
        recovery_action: RecoveryAction::None,
    };
    assert!(result.validate().is_ok());
    result.receipt = None;
    assert!(result.validate().is_err());
    result.status = ExecutionStatus::Unknown;
    result.error = Some(ContractError::NotFound);
    assert!(result.validate().is_err());
    result.recovery_action = RecoveryAction::QueryOriginal;
    assert!(result.validate().is_ok()); // lookup notFound is still unknown
    result.status = ExecutionStatus::Cancelled;
    assert!(result.validate().is_err());
    result.error = Some(ContractError::Cancelled);
    result.recovery_action = RecoveryAction::None;
    assert!(result.validate().is_ok());
}

#[test]
fn ct02_file_metadata_bounds_and_binding_are_checked() {
    let source = FileSource {
        snapshot_id: "snapshot-a".into(),
        blob: BlobRef {
            digest: "a".repeat(64),
            byte_length: Revision::new(100),
        },
        lease: ReadLease {
            lease_id: "reader-a".into(),
            owner_epoch: "epoch-a".into(),
            generation: Revision::new(1),
        },
    };
    let entry = ArchiveEntry {
        snapshot_id: source.snapshot_id.clone(),
        name: "资料/论文.pdf".into(),
        method: ArchiveMethod::Stored,
        crc32: 1,
        data_offset: Revision::new(10),
        compressed_length: Revision::new(90),
        expanded_length: Revision::new(90),
    };
    assert!(entry.validate_for(&source).is_ok());
    for name in [
        "../paper.pdf",
        "/paper.pdf",
        "a/../b",
        "a//b",
        "C:paper.pdf",
        "a\\b",
    ] {
        let mut bad = entry.clone();
        bad.name = name.into();
        assert!(bad.validate_for(&source).is_err());
    }
    let mut bad = entry.clone();
    bad.snapshot_id = "snapshot-b".into();
    assert_eq!(
        bad.validate_for(&source),
        Err(ContractError::BindingMismatch)
    );
    bad = entry.clone();
    bad.data_offset = Revision::new(u64::MAX);
    assert_eq!(bad.validate_for(&source), Err(ContractError::TextLimit));
    bad = entry.clone();
    bad.expanded_length = Revision::new(89);
    assert!(bad.validate_for(&source).is_err());
}
