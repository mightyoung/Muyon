// Evidence-only consumer of the existing Catalog. No replacement registry.
#[path = "../../../../../experiments/redesign/plugin-contract-lab/core/tests/support/mod.rs"]
mod support;
use muyon_plugin_contract_lab::{string, Json};
use support::*;

fn second() -> Json {
    json(
        &bundle()
            .encode()
            .replace("equipment_loan", "second")
            .replace("host-equipment-read", "second-read"),
    )
}

fn publish(catalog: &mut muyon_plugin_contract_lab::Catalog, value: Json) -> Json {
    call(
        catalog,
        "register",
        vec![
            ("bundle", value),
            ("host_bindings", json(r#"["second-read"]"#)),
        ],
    )
}

#[test]
fn every_declaration_stage_rejects_without_reserving_namespace_or_binding() {
    for stage in [
        "data_duplicate",
        "relation_duplicate",
        "operation_duplicate",
        "view_duplicate",
        "dependency",
        "schema",
        "binding",
    ] {
        let mut catalog = admitted();
        let before = stats(&mut catalog);
        let mut invalid = second();
        let expected = match stage {
            "data_duplicate" | "relation_duplicate" | "operation_duplicate" | "view_duplicate" => {
                let (key, code) = match stage {
                    "data_duplicate" => ("data", "duplicate_data"),
                    "relation_duplicate" => ("relations", "duplicate_relation"),
                    "operation_duplicate" => ("operations", "host_binding"),
                    _ => ("views", "view_name"),
                };
                let mut rows = field(&invalid, key).array().unwrap().to_vec();
                rows.push(rows[0].clone());
                put(&mut invalid, key, Json::Array(rows));
                code
            }
            "dependency" => {
                put(
                    row(&mut invalid, "views", 0),
                    "operation_refs",
                    json(r#"["second/missing@1"]"#),
                );
                "view_operation"
            }
            "schema" => {
                // Unknown schema keyword must fail closed.
                let data = row(&mut invalid, "data", 0);
                let mut schema = field(data, "schema").clone();
                put(&mut schema, "pattern", string(".*"));
                put(data, "schema", schema);
                "unexpected_or_missing_field"
            }
            "binding" => {
                put(
                    row(&mut invalid, "operations", 0),
                    "binding_id",
                    string("uninstalled-binding"),
                );
                "host_binding"
            }
            _ => unreachable!(),
        };
        let rejected = publish(&mut catalog, invalid);
        expect_code(&rejected, expected);
        assert_eq!(
            stats(&mut catalog),
            before,
            "partial publication at {stage}"
        );
        let repaired = publish(&mut catalog, second());
        assert!(
            ok(&repaired),
            "failed {stage} reserved identity: {}",
            repaired.encode()
        );
        assert_eq!(field(&repaired, "generation"), &json("2"));
    }
}

#[test]
fn rejected_publication_preserves_existing_prepared_admission() {
    let mut catalog = admitted();
    let pending = ticket(&mut catalog);
    let mut invalid = second();
    put(
        row(&mut invalid, "views", 0),
        "operation_refs",
        json(r#"["second/missing@1"]"#),
    );
    expect_code(&publish(&mut catalog, invalid), "view_operation");
    assert!(ok(&invoke(&mut catalog, pending.clone(), authority())));
    assert!(ok(&accept(
        &mut catalog,
        pending,
        authority(),
        receipt(),
        projection()
    )));
    assert_eq!(
        field(&stats(&mut catalog), "execution_requests"),
        &json("1")
    );
}

#[test]
fn successful_publication_invalidates_previous_generation_before_dispatch() {
    let mut catalog = admitted();
    let pending = ticket(&mut catalog);
    assert!(ok(&publish(&mut catalog, second())));
    expect_code(
        &invoke(&mut catalog, pending, authority()),
        "stale_authority",
    );
    assert_eq!(
        field(&stats(&mut catalog), "execution_requests"),
        &json("0")
    );
}

#[test]
fn closed_catalog_refuses_late_publication_and_new_admission() {
    let mut catalog = admitted();
    let pending = ticket(&mut catalog);
    assert!(ok(&call(&mut catalog, "close", vec![])));
    let before = stats(&mut catalog);
    expect_code(&publish(&mut catalog, second()), "closed");
    expect_code(&prepare(&mut catalog), "closed");
    expect_code(&invoke(&mut catalog, pending, authority()), "closed");
    assert_eq!(stats(&mut catalog), before);
    assert_eq!(field(&before, "pending"), &json("0"));
}
