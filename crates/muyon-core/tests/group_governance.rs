//! Socket-free contract tests; the included module can also run with rustc --test.
#[path = "../src/group_governance/mod.rs"]
mod group_governance;
use group_governance::*;
use std::collections::BTreeSet;

fn set(xs: &[&str]) -> BTreeSet<String> {
    xs.iter().map(|x| x.to_string()).collect()
}
fn grant() -> Grant {
    Grant {
        scopes: set(&["project:a"]),
        permissions: set(&["read"]),
    }
}
fn config() -> GroupConfig {
    GroupConfig {
        schema_version: 1,
        revision: 4,
        owner_user_id: "user".into(),
        admin_user_ids: set(&["admin"]),
        mode: Mode::HostOnly,
        coordinator_id: None,
    }
}
fn identity() -> Identity {
    Identity {
        workspace_id: "workspace".into(),
        owner_epoch: "host-epoch".into(),
        run_id: "run".into(),
        config_revision: 4,
        policy_revision: 2,
        plan_revision: 3,
        coordinator_epoch: 1,
    }
}
fn node(id: &str, deps: &[&str]) -> PlannedChild {
    PlannedChild {
        id: id.into(),
        parent_id: "root".into(),
        depth: 1,
        member_id: "bot".into(),
        grant: grant(),
        dependencies: set(deps),
    }
}
fn snapshot() -> HostSnapshot {
    HostSnapshot {
        identity: identity(),
        root_task_id: "root".into(),
        stopped: false,
        children: vec![],
        commands: vec![],
        budget: Budget {
            ceiling: 100,
            known_actual: 20,
            reserved: 10,
            unknown_request_ids: set(&[]),
        },
    }
}
fn command(id: &str) -> Command {
    Command {
        id: id.into(),
        identity: identity(),
        child_id: "a".into(),
        payload_digest: "host-canonical-digest".into(),
        reservation: 5,
    }
}
fn members() -> Vec<Member> {
    vec![Member {
        id: "bot".into(),
        grant: grant(),
    }]
}
fn check(s: &HostSnapshot, p: &[PlannedChild], c: &Command) -> Result<Decision, Error> {
    validate_host_only(
        &config(),
        s,
        p,
        &members(),
        &[grant(), grant(), grant(), grant()],
        &Limits { max_rounds: 8 },
        c,
    )
}
fn history(c: Command, state: CommandState) -> CommandRecord {
    CommandRecord {
        request_id: if c.id == "cmd" {
            "original-request".into()
        } else {
            format!("request-{}", c.id)
        },
        command: c,
        state,
    }
}
fn child(id: &str, state: ChildState) -> LedgerChild {
    LedgerChild {
        id: id.into(),
        parent_id: "root".into(),
        depth: 1,
        state,
    }
}

#[test]
fn collaborator_cannot_self_authorize_even_as_coordinator() {
    let mut c = config();
    c.coordinator_id = Some("bot".into());
    assert_eq!(
        validate_narrowing(&c, &Principal::Member("bot".into()), &grant(), &grant()),
        Err(Error::ManagementDenied)
    );
}
#[test]
fn human_admin_can_only_narrow_existing_grant() {
    let empty = Grant {
        scopes: set(&[]),
        permissions: set(&[]),
    };
    assert_eq!(
        validate_narrowing(
            &config(),
            &Principal::Human("admin".into()),
            &grant(),
            &empty
        ),
        Ok(())
    );
    let mut widened = grant();
    widened.permissions.insert("write".into());
    for actor in ["admin", "user", "stranger"] {
        assert!(validate_narrowing(
            &config(),
            &Principal::Human(actor.into()),
            &grant(),
            &widened
        )
        .is_err());
    }
}
#[test]
fn modes_roundtrip_by_explicit_name_and_unknown_fails_closed() {
    for (text, mode) in [
        ("host_only", Mode::HostOnly),
        ("fixed", Mode::Fixed),
        ("per_task", Mode::PerTask),
    ] {
        assert_eq!(Mode::try_from(text), Ok(mode));
        assert_eq!(mode.as_str(), text);
    }
    assert_eq!(Mode::try_from("automatic"), Err(Error::UnsupportedMode));
}
#[test]
fn unsupported_versions_and_ownerless_groups_are_rejected() {
    let mut c = config();
    c.schema_version = 2;
    assert_eq!(c.validate(), Err(Error::InvalidConfig));
    c = config();
    c.owner_user_id.clear();
    assert_eq!(c.validate(), Err(Error::InvalidConfig));
    c = config();
    c.coordinator_id = Some("bot".into());
    assert_eq!(c.validate(), Err(Error::InvalidConfig));
}
#[test]
fn represented_coordinator_modes_never_execute() {
    for mode in [Mode::Fixed, Mode::PerTask] {
        let mut c = config();
        c.mode = mode;
        c.coordinator_id = Some("bot".into());
        assert_eq!(c.validate(), Ok(()));
        assert_eq!(
            validate_host_only(
                &c,
                &snapshot(),
                &[node("a", &[])],
                &members(),
                &vec![grant(); 4],
                &Limits { max_rounds: 8 },
                &command("cmd")
            ),
            Err(Error::UnsupportedMode)
        );
    }
}
#[test]
fn deterministic_ready_order_uses_node_identity_and_dependencies() {
    let s = snapshot();
    let p = [node("z", &[]), node("b", &["a"]), node("a", &[])];
    assert_eq!(
        check(&s, &p, &command("cmd")),
        Ok(Decision::Eligible {
            child_id: "a".into()
        })
    );
    let mut wrong = command("cmd");
    wrong.child_id = "b".into();
    assert_eq!(check(&s, &p, &wrong), Err(Error::NotNextReady));
    let mut s = s;
    s.children.push(child("a", ChildState::Completed));
    let mut c = command("cmd");
    c.child_id = "b".into();
    assert_eq!(
        check(&s, &[node("z", &[]), node("b", &["a"])], &c),
        Ok(Decision::Eligible {
            child_id: "b".into()
        })
    );
}
#[test]
fn cycles_missing_dependencies_and_duplicate_nodes_are_rejected() {
    for p in [
        vec![node("a", &["b"]), node("b", &["a"])],
        vec![node("a", &["missing"])],
        vec![node("a", &[]), node("a", &[])],
    ] {
        assert_eq!(
            check(&snapshot(), &p, &command("cmd")),
            Err(Error::InvalidPlan)
        );
    }
}
#[test]
fn depth_two_and_foreign_parent_are_rejected() {
    let mut n = node("a", &[]);
    n.depth = 2;
    assert_eq!(
        check(&snapshot(), &[n], &command("cmd")),
        Err(Error::InvalidPlan)
    );
    let mut n = node("a", &[]);
    n.parent_id = "other-root".into();
    assert_eq!(
        check(&snapshot(), &[n], &command("cmd")),
        Err(Error::InvalidPlan)
    );
}
#[test]
fn every_authority_layer_and_member_scope_must_allow_the_request() {
    let mut n = node("a", &[]);
    n.grant.scopes.insert("project:b".into());
    assert_eq!(
        check(&snapshot(), &[n], &command("cmd")),
        Err(Error::ScopeDenied)
    );
    for layer in 0..4 {
        let mut layers = vec![grant(); 4];
        layers[layer].permissions.clear();
        assert_eq!(
            validate_host_only(
                &config(),
                &snapshot(),
                &[node("a", &[])],
                &members(),
                &layers,
                &Limits { max_rounds: 8 },
                &command("cmd")
            ),
            Err(Error::ScopeDenied)
        );
    }
    assert_eq!(
        validate_host_only(
            &config(),
            &snapshot(),
            &[node("a", &[])],
            &members(),
            &[],
            &Limits { max_rounds: 8 },
            &command("cmd")
        ),
        Err(Error::ScopeDenied)
    );
}
#[test]
fn non_member_is_rejected() {
    let mut n = node("a", &[]);
    n.member_id = "outsider".into();
    assert_eq!(
        check(&snapshot(), &[n], &command("cmd")),
        Err(Error::ScopeDenied)
    );
}
#[test]
fn eight_lifetime_children_and_two_active_slots_are_hard_caps() {
    let mut s = snapshot();
    s.children = (0..8)
        .map(|i| child(&format!("old{i}"), ChildState::Completed))
        .collect();
    assert_eq!(
        check(&s, &[node("a", &[])], &command("cmd")),
        Err(Error::ChildLimit)
    );
    s.children.pop();
    assert!(check(&s, &[node("a", &[])], &command("cmd")).is_ok());
    for state in [
        ChildState::Queued,
        ChildState::Running,
        ChildState::WaitingConfirmation,
        ChildState::Unknown,
    ] {
        let mut s = snapshot();
        s.children = vec![child("x", state), child("y", state)];
        assert_eq!(
            check(&s, &[node("a", &[])], &command("cmd")),
            Err(Error::ActiveLimit)
        );
    }
}
#[test]
fn ledger_corruption_and_unsupported_status_fail_closed() {
    let mut s = snapshot();
    s.children = vec![
        child("x", ChildState::Completed),
        child("x", ChildState::Completed),
    ];
    assert_eq!(
        check(&s, &[node("a", &[])], &command("cmd")),
        Err(Error::InvalidLedger)
    );
    assert_eq!(ChildState::try_from("new_state"), Err(Error::InvalidLedger));
}
#[test]
fn duplicate_command_returns_only_original_receipt_even_when_unknown() {
    let mut s = snapshot();
    s.commands
        .push(history(command("cmd"), CommandState::Unknown));
    s.budget
        .unknown_request_ids
        .insert("original-request".into());
    let before = s.clone();
    assert_eq!(
        check(&s, &[], &command("cmd")),
        Ok(Decision::LookupOriginal {
            request_id: "original-request".into(),
            state: CommandState::Unknown
        })
    );
    assert_eq!(s, before);
    let mut changed = command("cmd");
    changed.payload_digest = "changed".into();
    assert_eq!(check(&s, &[], &changed), Err(Error::CommandConflict));
}
#[test]
fn stale_host_epoch_leader_epoch_or_configuration_never_executes() {
    for field in 0..7 {
        let s = snapshot();
        let mut c = command("cmd");
        match field {
            0 => c.identity.owner_epoch = "old".into(),
            1 => c.identity.coordinator_epoch = 0,
            2 => c.identity.config_revision = 3,
            3 => c.identity.policy_revision = 1,
            4 => c.identity.plan_revision = 2,
            5 => c.identity.run_id = "other".into(),
            _ => c.identity.workspace_id = "other".into(),
        };
        assert_eq!(check(&s, &[node("a", &[])], &c), Err(Error::StaleIdentity));
    }
}
#[test]
fn unknown_budget_keeps_reserve_and_blocks_new_command() {
    let mut s = snapshot();
    s.budget.reserved = 2620;
    s.budget.ceiling = 10000;
    s.budget.unknown_request_ids = set(&["old-request-1", "old-request-2"]);
    let before = s.clone();
    assert_eq!(
        check(&s, &[node("a", &[])], &command("new")),
        Err(Error::ReconcileOriginal)
    );
    assert_eq!(s, before);
    s.budget.unknown_request_ids.clear();
    s.commands
        .push(history(command("old"), CommandState::Unknown));
    assert_eq!(
        check(&s, &[node("a", &[])], &command("new")),
        Err(Error::ReconcileOriginal)
    );
}
#[test]
fn budget_overflow_and_exhaustion_never_become_zero_cost() {
    let mut s = snapshot();
    s.budget.ceiling = 34;
    assert_eq!(
        check(&s, &[node("a", &[])], &command("cmd")),
        Err(Error::BudgetLimit)
    );
    s.budget.ceiling = u64::MAX;
    s.budget.known_actual = u64::MAX;
    assert_eq!(
        check(&s, &[node("a", &[])], &command("cmd")),
        Err(Error::BudgetLimit)
    );
}
#[test]
fn rounds_count_original_dispatch_history_across_restarts_and_stops() {
    let mut s = snapshot();
    s.commands = (0..8)
        .map(|i| history(command(&format!("old{i}")), CommandState::Completed))
        .collect();
    let restored = s.clone();
    assert_eq!(
        check(&restored, &[node("a", &[])], &command("new")),
        Err(Error::RoundLimit)
    );
    s.commands.pop();
    assert!(check(&s, &[node("a", &[])], &command("new")).is_ok());
    s.stopped = true;
    assert_eq!(
        check(&s, &[node("a", &[])], &command("new")),
        Err(Error::Stopped)
    );
}

#[test]
fn all_duplicate_states_only_lookup_and_submitted_blocks_new_dispatch() {
    for state in [
        CommandState::Prepared,
        CommandState::Submitted,
        CommandState::Unknown,
        CommandState::Completed,
        CommandState::Failed,
    ] {
        let mut s = snapshot();
        s.stopped = true;
        s.commands.push(history(command("cmd"), state));
        assert_eq!(
            check(&s, &[], &command("cmd")),
            Ok(Decision::LookupOriginal {
                request_id: "original-request".into(),
                state
            })
        );
    }
    let mut s = snapshot();
    s.commands
        .push(history(command("old"), CommandState::Submitted));
    assert_eq!(
        check(&s, &[node("a", &[])], &command("new")),
        Err(Error::ReconcileOriginal)
    );
}
#[test]
fn failed_dependencies_do_not_run_and_cancelled_children_keep_lifetime_slots() {
    let mut s = snapshot();
    s.children.push(child("dependency", ChildState::Failed));
    assert_eq!(
        check(&s, &[node("a", &["dependency"])], &command("cmd")),
        Err(Error::NotNextReady)
    );
    s.children = (0..8)
        .map(|i| child(&format!("cancelled{i}"), ChildState::Cancelled))
        .collect();
    assert_eq!(
        check(&s, &[node("a", &[])], &command("cmd")),
        Err(Error::ChildLimit)
    );
}
#[test]
fn duplicate_request_identity_and_stale_config_are_not_valid_host_views() {
    let mut s = snapshot();
    let mut a = history(command("x"), CommandState::Completed);
    let mut b = history(command("y"), CommandState::Completed);
    a.request_id = "same".into();
    b.request_id = "same".into();
    s.commands = vec![a, b];
    assert_eq!(
        check(&s, &[node("a", &[])], &command("new")),
        Err(Error::InvalidLedger)
    );
    let mut s = snapshot();
    s.identity.config_revision = 5;
    let mut c = command("new");
    c.identity = s.identity.clone();
    assert_eq!(check(&s, &[node("a", &[])], &c), Err(Error::StaleIdentity));
}

#[test]
fn unknown_child_blocks_even_when_request_and_budget_projection_omit_it() {
    let mut s = snapshot();
    s.children.push(child("unresolved", ChildState::Unknown));
    let before = s.clone();
    assert_eq!(
        check(&s, &[node("a", &[])], &command("new")),
        Err(Error::ReconcileOriginal)
    );
    assert_eq!(s, before);
}
