use muyon_core::{contract, services};
#[path = "../src/services/skills.rs"]
mod skills;
use contract::{Revision, Scope};
use serde_json::{json, Value};
use services::types::{decode_strict, Digest, ErrorCode, ScopeRef};
use sha2::{Digest as _, Sha256};
use skills::*;

fn fixture() -> SkillRegistrySnapshot {
    let scope = ScopeRef {
        scope: Scope {
            workspace_id: "w".into(),
            project_id: Some("p".into()),
        },
        account_id: Some("a".into()),
        scope_generation: Revision::new(1),
    };
    let skills = builtin_descriptors();
    assert_eq!(skills.len(), 2, "two compiled descriptions required");
    SkillRegistrySnapshot {
        catalog_revision: Revision::new(1),
        bindings: vec![SkillBinding {
            binding_id: "binding:1".into(),
            scope,
            bot_id: None,
            revision: Revision::new(1),
            skill: skills[0].reference.clone(),
            enabled: true,
        }],
        skills,
    }
}
#[test]
fn catalog_is_read_only() {
    let s = fixture();
    let before = s.clone();
    assert_eq!(list_skills(&s).len(), 2);
    assert!(validate_catalog(&s).is_ok());
    for r in list_skills(&s) {
        assert_eq!(get_descriptor(&s, &r).unwrap().reference, r);
    }
    assert_eq!(get_binding(&s, "binding:1").unwrap(), &s.bindings[0]);
    assert_eq!(s, before);
    // No invocation port/DB/context is supplied. Compiled resource reads are include_str only.
    for (id, bytes, capability) in [
        (
            "supplier-overview",
            include_bytes!("../src/agent/skills/supplier-overview/SKILL.md").as_slice(),
            "supplier_list",
        ),
        (
            "paper-overview",
            include_bytes!("../src/agent/skills/paper-overview/SKILL.md").as_slice(),
            "paper_list",
        ),
    ] {
        let d = s
            .skills
            .iter()
            .find(|d| d.reference.skill_id == id)
            .unwrap();
        assert_eq!(
            d.reference.content_digest.as_str(),
            Sha256::digest(bytes)
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>()
        );
        assert_eq!(d.required_capabilities, vec![capability]);
        let wire = serde_json::to_value(d).unwrap();
        assert!(wire.get("body").is_none());
        assert!(wire.get("approved").is_none());
    }
}
#[test]
fn exact_versions_coexist_and_digest_substitution_is_rejected() {
    let mut s = fixture();
    let original = s.skills[0].clone();
    let mut v2 = original.clone();
    v2.reference.version = "builtin-v2".into();
    v2.reference.content_digest = Digest::parse(&"b".repeat(64)).unwrap();
    s.skills.push(v2.clone());
    assert_eq!(get_descriptor(&s, &original.reference).unwrap(), &original);
    assert_eq!(get_descriptor(&s, &v2.reference).unwrap(), &v2);
    let mut substituted = original.reference.clone();
    substituted.content_digest = Digest::parse(&"c".repeat(64)).unwrap();
    assert_eq!(
        get_descriptor(&s, &substituted).unwrap_err().code,
        ErrorCode::StaleRevision
    );
    s.skills.push(SkillDescriptor {
        reference: substituted,
        ..original
    });
    assert_eq!(
        validate_catalog(&s).unwrap_err().code,
        ErrorCode::InvalidArgument
    );
    assert!(list_skills(&s).is_empty());
    assert!(get_binding(&s, "binding:1").is_err());
}
#[test]
fn binding_cas_and_upgrade() {
    let s = fixture();
    let current = &s.bindings[0];
    let mut next = current.clone();
    next.revision = Revision::new(2);
    next.skill.version = "builtin-v2".into();
    assert_eq!(
        validate_binding_update(current, &Revision::new(0), &next)
            .unwrap_err()
            .code,
        ErrorCode::StaleRevision
    );
    assert!(validate_binding_update(current, &current.revision, &next).is_ok());
    for field in ["id", "scope", "bot", "revision"] {
        let mut bad = next.clone();
        match field {
            "id" => bad.binding_id = "other".into(),
            "scope" => bad.scope.scope_generation = Revision::new(2),
            "bot" => bad.bot_id = Some("other".into()),
            _ => bad.revision = Revision::new(4),
        }
        assert!(
            validate_binding_update(current, &current.revision, &bad).is_err(),
            "{field}"
        );
    }
    next.enabled = false;
    assert!(validate_binding_update(current, &current.revision, &next).is_ok());
    assert!(current.enabled); // candidate validation never changes the stored snapshot
    assert!(get_binding(&s, "absent").is_err());
    let mut absent = current.skill.clone();
    absent.skill_id = "absent".into();
    assert!(get_descriptor(&s, &absent).is_err());
}
#[test]
fn fixture_roundtrip_and_unknown_authority_rejection() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../docs/contracts/public-services-v02/fixtures/skills.json"
    ))
    .unwrap();
    assert_eq!(fixture["contract_major"], 1);
    assert_eq!(fixture["schema_major"], 1);
    let s = decode_strict::<SkillRegistrySnapshot>(&fixture["snapshot"].to_string()).unwrap();
    assert!(validate_catalog(&s).is_ok());
    assert_eq!(s.skills, builtin_descriptors());
    assert_eq!(serde_json::to_value(s).unwrap(), fixture["snapshot"]);
    for field in ["approved", "allowed_tools", "granted_capabilities"] {
        let mut wire = fixture["snapshot"]["bindings"][0].clone();
        wire[field] = json!(true);
        assert!(decode_strict::<SkillBinding>(&wire.to_string()).is_err());
    }
}

#[test]
fn malformed_catalog_is_distinct_from_a_valid_empty_catalog() {
    let empty = SkillRegistrySnapshot {
        catalog_revision: Revision::new(1),
        skills: vec![],
        bindings: vec![],
    };
    let mut malformed = fixture();
    malformed.skills.push(malformed.skills[0].clone());
    assert!(validate_catalog(&empty).is_ok());
    assert!(validate_catalog(&malformed).is_err());
    assert_ne!(list_skills(&empty), list_skills(&malformed));
}
