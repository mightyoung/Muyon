use muyon_core::{
    business, contract, documents,
    domains::{inquiry_projection, research_projection},
    research, services,
};

use business::SupplierRecord;
use contract::{BlobRef, Revision, Scope, SupplierPayload};
use documents::{DocumentFormat, DocumentRef};
use inquiry_projection::project_supplier;
use research::PaperRecord;
use research_projection::{project_paper, DocumentBindingView};
use services::types::{ErrorCode, ScopeRef};

fn scope() -> ScopeRef {
    ScopeRef {
        scope: Scope {
            workspace_id: "workspace-a".into(),
            project_id: Some("project-a".into()),
        },
        account_id: Some("account-a".into()),
        scope_generation: Revision::new(8),
    }
}
fn document(scope: &ScopeRef) -> DocumentRef {
    DocumentRef::new(
        scope.scope.clone(),
        "document-a",
        Revision::parse("18446744073709551615").unwrap(),
        DocumentFormat::Pdf,
    )
    .unwrap()
}
fn paper() -> PaperRecord {
    PaperRecord {
        id: "paper-a".into(),
        project_id: "project-a".into(),
        kind: "papers".into(),
        title: "A paper".into(),
        raw_json: "secret-raw /internal/catalog.sqlite".into(),
        source_id: None,
        source_record_id: None,
        source_revision: None,
        revision: Revision::parse("18446744073709551615").unwrap(),
        manual: true,
        attachments: vec![BlobRef {
            digest: "a".repeat(64),
            byte_length: Revision::new(5),
        }],
    }
}
fn supplier() -> SupplierRecord {
    SupplierRecord {
        id: "supplier-a".into(),
        payload: SupplierPayload {
            name: "A supplier".into(),
            aliases: vec![],
            address: Some("secret-address".into()),
            categories: vec![],
            notes: Some("secret-notes /internal/supplier.sqlite".into()),
            merged_into: None,
            rating: None,
            rating_note: None,
        },
        revision: Revision::parse("9007199254740993").unwrap(),
        deleted: false,
    }
}

#[test]
fn shared_documents_are_references_only() {
    let scope = scope();
    let reference = document(&scope);
    let research = project_paper(&paper(), &scope, std::slice::from_ref(&reference)).unwrap();
    let inquiry = project_supplier(&supplier(), &scope, std::slice::from_ref(&reference)).unwrap();
    assert_eq!(
        research.documents,
        vec![DocumentBindingView::Bound(reference.clone())]
    );
    assert_eq!(
        inquiry.documents,
        vec![DocumentBindingView::Bound(reference)]
    );
    let unbound = DocumentBindingView::Unbound {
        reason: "document_binding_unavailable".into(),
    };
    assert_eq!(
        project_paper(&paper(), &scope, &[]).unwrap().documents,
        vec![unbound.clone()]
    );
    assert_eq!(
        project_supplier(&supplier(), &scope, &[])
            .unwrap()
            .documents,
        vec![unbound]
    );
    let mut no_attachment = paper();
    no_attachment.attachments.clear();
    assert!(project_paper(&no_attachment, &scope, &[])
        .unwrap()
        .documents
        .is_empty());
    let mut two = paper();
    two.attachments.push(two.attachments[0].clone());
    assert_eq!(project_paper(&two, &scope, &[]).unwrap().documents.len(), 2);
}

#[test]
fn domain_revision_is_exact() {
    let scope = scope();
    let research = project_paper(&paper(), &scope, &[document(&scope)]).unwrap();
    let inquiry = project_supplier(&supplier(), &scope, &[]).unwrap();
    assert_eq!(research.paper_id, "paper-a");
    assert_eq!(research.project_id, "project-a");
    assert_eq!(research.title, "A paper");
    assert_eq!(inquiry.supplier_id, "supplier-a");
    assert_eq!(inquiry.name, "A supplier");
    assert_eq!(inquiry.scope, scope);
    let research_json = serde_json::to_value(&research).unwrap();
    let inquiry_json = serde_json::to_value(&inquiry).unwrap();
    assert_eq!(research_json["revision"], "18446744073709551615");
    assert_eq!(inquiry_json["revision"], "9007199254740993");
    assert_eq!(
        serde_json::from_value::<research_projection::ResearchView>(research_json.clone()).unwrap(),
        research
    );
    assert_eq!(
        serde_json::from_value::<inquiry_projection::SupplierView>(inquiry_json.clone()).unwrap(),
        inquiry
    );
    for serialized in [research_json.to_string(), inquiry_json.to_string()] {
        for forbidden in [
            "secret",
            "/internal",
            "raw_json",
            "byte_length",
            "digest",
            "notes",
            "address",
        ] {
            assert!(!serialized.contains(forbidden), "leaked {forbidden}");
        }
    }
}

#[test]
fn references_and_paper_must_match_trusted_host_scope() {
    let scope = scope();
    for bad_scope in [
        Scope {
            workspace_id: "workspace-b".into(),
            ..scope.scope.clone()
        },
        Scope {
            project_id: Some("project-b".into()),
            ..scope.scope.clone()
        },
        Scope {
            project_id: None,
            ..scope.scope.clone()
        },
    ] {
        let mut other = scope.clone();
        other.scope = bad_scope;
        let reference = document(&other);
        assert_eq!(
            project_paper(&paper(), &scope, std::slice::from_ref(&reference))
                .unwrap_err()
                .code,
            ErrorCode::ScopeChanged
        );
        assert_eq!(
            project_supplier(&supplier(), &scope, &[reference])
                .unwrap_err()
                .code,
            ErrorCode::ScopeChanged
        );
    }
    let mut wrong_project = scope.clone();
    wrong_project.scope.project_id = Some("project-b".into());
    assert_eq!(
        project_paper(&paper(), &wrong_project, &[])
            .unwrap_err()
            .code,
        ErrorCode::ScopeChanged
    );
    wrong_project.scope.project_id = None;
    assert!(project_paper(&paper(), &wrong_project, &[]).is_err());
    let valid = document(&scope);
    let invalid = document(&wrong_project);
    assert!(project_supplier(&supplier(), &scope, &[valid, invalid]).is_err());
}

#[test]
fn deleted_supplier_is_not_current_and_invalid_scope_is_rejected() {
    let scope = scope();
    let mut deleted = supplier();
    deleted.deleted = true;
    assert_eq!(
        project_supplier(&deleted, &scope, &[]).unwrap_err().code,
        ErrorCode::ResourceExpired
    );
    let mut invalid = scope;
    invalid.scope.workspace_id = "/internal/workspace".into();
    assert_eq!(
        project_supplier(&supplier(), &invalid, &[])
            .unwrap_err()
            .code,
        ErrorCode::InvalidArgument
    );
    assert!(project_paper(&paper(), &invalid, &[]).is_err());
}
