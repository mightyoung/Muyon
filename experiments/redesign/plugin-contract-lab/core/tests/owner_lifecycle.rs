mod support;
use muyon_plugin_contract_lab::{Catalog, DrainState, Json, OwnerLease};
use std::sync::{Arc, Mutex};
use support::*;

fn enroll(c: &mut Catalog) -> OwnerLease {
    c.register_owned(bundle(), vec!["host-equipment-read".into()], vec![])
        .unwrap()
}
fn dispatch(c: &mut Catalog, owner: &OwnerLease) -> (Json, muyon_plugin_contract_lab::WorkLease) {
    let t = ticket(c);
    c.dispatch_owned(owner, t.string().unwrap(), authority())
        .unwrap()
}
fn consumer(c: &mut Catalog) -> muyon_plugin_contract_lab::Result<OwnerLease> {
    let mut b = bundle();
    put(
        &mut b,
        "module_id",
        muyon_plugin_contract_lab::string("consumer"),
    );
    for key in ["data", "relations", "views"] {
        put(&mut b, key, json("[]"));
    }
    put(
        row(&mut b, "operations", 0),
        "binding_id",
        muyon_plugin_contract_lab::string("consumer-read"),
    );
    c.register_owned(
        b,
        vec!["consumer-read".into()],
        vec![
            "equipment_loan/equipment@1".into(),
            "equipment_loan/loan@1".into(),
        ],
    )
}

#[test]
fn stale_disposer_cannot_delete_replacement_epoch_or_close_its_resource() {
    let mut c = Catalog::new();
    let first = enroll(&mut c);
    assert_eq!(
        c.stop_owner(&first).unwrap(),
        DrainState::Draining { in_flight: 0 }
    );
    assert_eq!(
        c.release_owner(&first, || Ok(())).unwrap(),
        DrainState::Released
    );
    let next = enroll(&mut c);
    assert_ne!(first.epoch(), next.epoch());
    assert_eq!(
        c.release_owner(&first, || panic!("old disposer ran twice"))
            .unwrap(),
        DrainState::Released
    );
    assert_eq!(c.stop_owner(&first).unwrap(), DrainState::Released);
    assert_eq!(c.owner_state(&next).unwrap(), DrainState::Active);
    let (_, work) = dispatch(&mut c, &next);
    c.settle_work(&work, || Ok(())).unwrap();
    assert_eq!(field(&stats(&mut c), "execution_requests"), &json("1"));
}

#[test]
fn foreign_catalog_leases_cannot_fence_dispatch_settle_or_release() {
    let mut a = Catalog::new();
    let a_owner = enroll(&mut a);
    let (_, a_work) = dispatch(&mut a, &a_owner);
    let mut b = Catalog::new();
    let b_owner = enroll(&mut b);
    let before = stats(&mut b);
    assert_eq!(b.stop_owner(&a_owner).unwrap_err(), "foreign_owner");
    assert_eq!(
        b.release_owner(&a_owner, || panic!("foreign close"))
            .unwrap_err(),
        "foreign_owner"
    );
    assert_eq!(
        b.settle_work(&a_work, || panic!("foreign persistence"))
            .unwrap_err(),
        "foreign_work"
    );
    let t = ticket(&mut b);
    assert_eq!(
        b.dispatch_owned(&a_owner, t.string().unwrap(), authority())
            .unwrap_err(),
        "foreign_owner"
    );
    assert_eq!(b.owner_state(&b_owner).unwrap(), DrainState::Active);
    let after = stats(&mut b);
    assert_eq!(field(&after, "generation"), field(&before, "generation"));
    assert_eq!(field(&after, "execution_requests"), &json("0"));
}

#[test]
fn stopping_fences_discovery_prepare_old_ticket_and_late_reenrollment() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    let t = ticket(&mut c);
    c.stop_owner(&owner).unwrap();
    let visible = call(&mut c, "discover", vec![("authority", authority())]);
    assert_eq!(field(&visible, "operations"), &json("[]"));
    expect_code(&prepare(&mut c), "owner_stopping");
    assert!(c
        .dispatch_owned(&owner, t.string().unwrap(), authority())
        .is_err());
    assert_eq!(
        c.register_owned(bundle(), vec!["host-equipment-read".into()], vec![])
            .unwrap_err(),
        "module_identity"
    );
    assert_eq!(consumer(&mut c).unwrap_err(), "unresolved_data");
    assert_eq!(field(&stats(&mut c), "execution_requests"), &json("0"));
    let before = stats(&mut c);
    c.stop_owner(&owner).unwrap();
    assert_eq!(stats(&mut c), before);
}

#[test]
fn managed_dispatch_cannot_bypass_tracking_via_wire_and_authority_still_denies() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    let t = ticket(&mut c);
    expect_code(
        &invoke(&mut c, t.clone(), authority()),
        "owned_dispatch_required",
    );
    let mut denied = authority();
    put(&mut denied, "allowed", Json::Bool(false));
    assert!(c
        .dispatch_owned(&owner, t.string().unwrap(), denied)
        .is_err());
    assert_eq!(field(&stats(&mut c), "execution_requests"), &json("0"));
    c.stop_owner(&owner).unwrap();
    assert_eq!(
        c.owner_state(&owner).unwrap(),
        DrainState::Draining { in_flight: 0 }
    );
}

#[test]
fn dependent_bundle_must_be_released_before_provider_stop_without_partial_change() {
    let mut c = Catalog::new();
    let provider = enroll(&mut c);
    let dependent = consumer(&mut c).unwrap();
    let before = stats(&mut c);
    assert_eq!(c.stop_owner(&provider).unwrap_err(), "owner_has_dependents");
    assert_eq!(stats(&mut c), before);
    assert_eq!(c.owner_state(&provider).unwrap(), DrainState::Active);
    c.stop_owner(&dependent).unwrap();
    assert_eq!(c.stop_owner(&provider).unwrap_err(), "owner_has_dependents");
    c.release_owner(&dependent, || Ok(())).unwrap();
    c.stop_owner(&provider).unwrap();
    c.release_owner(&provider, || Ok(())).unwrap();
    let s = stats(&mut c);
    for key in [
        "data_count",
        "operation_count",
        "relation_count",
        "view_count",
    ] {
        assert_eq!(field(&s, key), &json("0"));
    }
    enroll(&mut c);
}

#[test]
fn cancel_and_close_do_not_claim_handler_quiescence_or_release_resource() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    let (reply, work) = dispatch(&mut c, &owner);
    assert!(ok(&reply));
    let t = work.ticket();
    assert!(ok(&call(
        &mut c,
        "cancel",
        vec![("ticket", muyon_plugin_contract_lab::string(t))]
    )));
    assert!(ok(&call(&mut c, "close", vec![])));
    assert_eq!(
        c.owner_state(&owner).unwrap(),
        DrainState::Draining { in_flight: 1 }
    );
    assert_eq!(
        c.release_owner(&owner, || panic!("live handler resource released"))
            .unwrap_err(),
        "owner_draining"
    );
    c.settle_work(&work, || Ok(())).unwrap();
    assert_eq!(
        c.release_owner(&owner, || Ok(())).unwrap(),
        DrainState::Released
    );
    expect_code(&register(&mut c, bundle()), "closed");
}

#[test]
fn failed_persistence_or_close_retains_fencing_and_completion_is_idempotent() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    let (_, work) = dispatch(&mut c, &owner);
    c.stop_owner(&owner).unwrap();
    assert_eq!(
        c.settle_work(&work, || Err("durable_unknown_failed".into()))
            .unwrap_err(),
        "durable_unknown_failed"
    );
    assert_eq!(
        c.owner_state(&owner).unwrap(),
        DrainState::Draining { in_flight: 1 }
    );
    assert_eq!(
        c.release_owner(&owner, || panic!("not drained"))
            .unwrap_err(),
        "owner_draining"
    );
    c.settle_work(&work, || Ok(())).unwrap();
    c.settle_work(&work, || panic!("persistence replayed"))
        .unwrap();
    let before = stats(&mut c);
    assert_eq!(
        c.release_owner(&owner, || Err("close_failed".into()))
            .unwrap_err(),
        "close_failed"
    );
    assert_eq!(stats(&mut c), before);
    assert_eq!(
        c.owner_state(&owner).unwrap(),
        DrainState::Draining { in_flight: 0 }
    );
    assert!(c
        .register_owned(bundle(), vec!["host-equipment-read".into()], vec![])
        .is_err());
    assert_eq!(
        c.release_owner(&owner, || Ok(())).unwrap(),
        DrainState::Released
    );
}

#[test]
fn concurrent_stop_retains_blocked_work_until_host_settlement() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    let (_, work) = dispatch(&mut c, &owner);
    let c = Arc::new(Mutex::new(c));
    let (ready_tx, ready_rx) = std::sync::mpsc::channel();
    let (finish_tx, finish_rx) = std::sync::mpsc::channel();
    let worker_catalog = c.clone();
    let worker = std::thread::spawn(move || {
        ready_tx.send(()).unwrap();
        finish_rx
            .recv_timeout(std::time::Duration::from_secs(2))
            .unwrap();
        worker_catalog
            .lock()
            .unwrap()
            .settle_work(&work, || Ok(()))
            .unwrap();
    });
    ready_rx
        .recv_timeout(std::time::Duration::from_secs(2))
        .unwrap();
    {
        let mut c = c.lock().unwrap();
        assert_eq!(
            c.stop_owner(&owner).unwrap(),
            DrainState::Draining { in_flight: 1 }
        );
        assert_eq!(
            c.release_owner(&owner, || panic!("blocked work released"))
                .unwrap_err(),
            "owner_draining"
        );
        expect_code(&prepare(&mut c), "owner_stopping");
    }
    finish_tx.send(()).unwrap();
    worker.join().unwrap();
    let mut c = c.lock().unwrap();
    assert_eq!(
        c.release_owner(&owner, || Ok(())).unwrap(),
        DrainState::Released
    );
}

#[test]
fn active_owner_cannot_release_and_dropped_work_does_not_fake_drain() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    assert_eq!(
        c.release_owner(&owner, || panic!("active close"))
            .unwrap_err(),
        "owner_active"
    );
    let (_, work) = dispatch(&mut c, &owner);
    drop(work);
    assert_eq!(
        c.stop_owner(&owner).unwrap(),
        DrainState::Draining { in_flight: 1 }
    );
    assert_eq!(
        c.release_owner(&owner, || panic!("abandoned work released"))
            .unwrap_err(),
        "owner_draining"
    );
}

#[test]
fn accepted_projection_and_old_completion_do_not_release_unsettled_new_epoch() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    assert_eq!(
        owner.generation(),
        field(&stats(&mut c), "generation").integer().unwrap()
    );
    let t = ticket(&mut c);
    let (_, work) = c
        .dispatch_owned(&owner, t.string().unwrap(), authority())
        .unwrap();
    assert!(ok(&accept(&mut c, t, authority(), receipt(), projection())));
    assert_eq!(
        c.stop_owner(&owner).unwrap(),
        DrainState::Draining { in_flight: 1 }
    );
    c.settle_work(&work, || Ok(())).unwrap();
    c.release_owner(&owner, || Ok(())).unwrap();
    let replacement = enroll(&mut c);
    let (_, next_work) = dispatch(&mut c, &replacement);
    c.settle_work(&work, || panic!("old completion replayed"))
        .unwrap();
    c.stop_owner(&replacement).unwrap();
    assert_eq!(
        c.owner_state(&replacement).unwrap(),
        DrainState::Draining { in_flight: 1 }
    );
    c.settle_work(&next_work, || Ok(())).unwrap();
    c.release_owner(&replacement, || Ok(())).unwrap();
}

#[test]
fn owned_work_quota_refuses_without_consuming_ticket_and_settlement_restores_capacity() {
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    let mut work = Vec::new();
    for _ in 0..128 {
        let t = ticket(&mut c);
        let (_, w) = c
            .dispatch_owned(&owner, t.string().unwrap(), authority())
            .unwrap();
        assert!(ok(&call(&mut c, "cancel", vec![("ticket", t)])));
        work.push(w);
    }
    let t = ticket(&mut c);
    assert_eq!(
        c.dispatch_owned(&owner, t.string().unwrap(), authority())
            .unwrap_err(),
        "owner_work_limit"
    );
    c.settle_work(&work.remove(0), || Ok(())).unwrap();
    let (_, last) = c
        .dispatch_owned(&owner, t.string().unwrap(), authority())
        .unwrap();
    work.push(last);
    assert_eq!(
        c.stop_owner(&owner).unwrap(),
        DrainState::Draining { in_flight: 128 }
    );
    for w in work {
        c.settle_work(&w, || Ok(())).unwrap();
    }
    c.release_owner(&owner, || Ok(())).unwrap();
}

#[test]
fn exact_release_preserves_other_bundle_and_rejects_wrong_owner_dispatch() {
    let mut c = Catalog::new();
    let first = enroll(&mut c);
    let second_bundle = json(
        &bundle()
            .encode()
            .replace("equipment_loan", "other")
            .replace("host-equipment-read", "other-read"),
    );
    let second = c
        .register_owned(second_bundle, vec!["other-read".into()], vec![])
        .unwrap();
    let t = ticket(&mut c);
    assert_eq!(
        c.dispatch_owned(&second, t.string().unwrap(), authority())
            .unwrap_err(),
        "work_owner"
    );
    let (_, work) = c
        .dispatch_owned(&first, t.string().unwrap(), authority())
        .unwrap();
    c.settle_work(&work, || Ok(())).unwrap();
    c.stop_owner(&first).unwrap();
    c.release_owner(&first, || Ok(())).unwrap();
    let s = stats(&mut c);
    assert_eq!(field(&s, "data_count"), &json("2"));
    for key in ["operation_count", "relation_count", "view_count"] {
        assert_eq!(field(&s, key), &json("1"));
    }
    let second_authority = json(
        &authority()
            .encode()
            .replace("equipment_loan", "other")
            .replace("host-equipment-read", "other-read"),
    );
    let visible = call(&mut c, "discover", vec![("authority", second_authority)]);
    assert_eq!(field(&visible, "operations").array().unwrap().len(), 1);
    assert_eq!(c.owner_state(&second).unwrap(), DrainState::Active);
}

#[test]
fn plugin_json_cannot_supply_owner_or_use_disposer_commands() {
    let mut c = Catalog::new();
    let before = stats(&mut c);
    let injected = call(
        &mut c,
        "register",
        vec![
            ("bundle", bundle()),
            ("host_bindings", json(r#"["host-equipment-read"]"#)),
            ("owner_epoch", json("1")),
        ],
    );
    expect_code(&injected, "unexpected_or_missing_field");
    expect_code(&call(&mut c, "stop_owner", vec![]), "unsupported_command");
    assert_eq!(stats(&mut c), before);
    let owner = enroll(&mut c);
    assert_eq!(owner.epoch(), 1);
    assert_eq!(owner.generation(), 1);
}

#[test]
fn durable_host_marker_precedes_resource_release_and_business_bytes_survive() {
    use std::io::Write;
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    let dir = std::env::temp_dir().join(format!(
        "pip-owner-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    std::fs::create_dir(&dir).unwrap();
    let business = dir.join("business");
    let durable = dir.join("host-completion");
    std::fs::write(&business, b"preserve original business bytes").unwrap();
    let mut c = Catalog::new();
    let owner = enroll(&mut c);
    let (_, work) = dispatch(&mut c, &owner);
    c.stop_owner(&owner).unwrap();
    c.settle_work(&work, || {
        let mut file = std::fs::File::create(&durable).map_err(|e| e.to_string())?;
        file.write_all(b"host test unknown marker")
            .map_err(|e| e.to_string())?;
        file.sync_all().map_err(|e| e.to_string())
    })
    .unwrap();
    c.release_owner(&owner, || {
        assert_eq!(
            std::fs::read(&durable).unwrap(),
            b"host test unknown marker"
        );
        Ok(())
    })
    .unwrap();
    assert_eq!(
        std::fs::read(&business).unwrap(),
        b"preserve original business bytes"
    );
    std::fs::remove_dir_all(&dir).unwrap(); // only this test's uniquely owned files
}

#[test]
fn stop_wire_cancel_and_close_request_cooperative_cancel_without_settling_work() {
    for cause in ["stop", "cancel", "close"] {
        let mut c = Catalog::new();
        let owner = enroll(&mut c);
        let (_, work) = dispatch(&mut c, &owner);
        assert!(!work.cancel_requested());
        match cause {
            "stop" => {
                c.stop_owner(&owner).unwrap();
            }
            "cancel" => {
                assert!(ok(&call(
                    &mut c,
                    "cancel",
                    vec![("ticket", muyon_plugin_contract_lab::string(work.ticket()))]
                )));
                assert!(work.cancel_requested());
                c.stop_owner(&owner).unwrap();
            }
            _ => {
                assert!(ok(&call(&mut c, "close", vec![])));
            }
        }
        assert!(
            work.cancel_requested(),
            "missing cooperative cancellation on {cause}"
        );
        assert_eq!(
            c.owner_state(&owner).unwrap(),
            DrainState::Draining { in_flight: 1 }
        );
        c.settle_work(&work, || Ok(())).unwrap();
        c.release_owner(&owner, || Ok(())).unwrap();
    }
}
