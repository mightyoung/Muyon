//! Synthetic host projections only. No sockets, models or user's documents.
#[allow(dead_code)]
#[path = "../src/group_governance/mod.rs"]
mod group_governance;
#[allow(dead_code)]
#[path = "../src/group_runtime/mod.rs"]
mod group_runtime;
use group_governance::*;
use group_runtime::*;
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
fn members() -> Vec<Member> {
    ["a", "b"]
        .iter()
        .map(|id| Member {
            id: (*id).into(),
            grant: grant(),
        })
        .collect()
}
fn config(mode: Mode) -> GroupConfig {
    GroupConfig {
        schema_version: 1,
        revision: 1,
        owner_user_id: "owner".into(),
        admin_user_ids: set(&["admin"]),
        mode,
        coordinator_id: if mode == Mode::Fixed {
            Some("a".into())
        } else {
            None
        },
    }
}
fn host() -> HostSnapshot {
    HostSnapshot {
        identity: Identity {
            workspace_id: "ws".into(),
            owner_epoch: "lease".into(),
            run_id: "run".into(),
            config_revision: 1,
            policy_revision: 1,
            plan_revision: 1,
            coordinator_epoch: 1,
        },
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
fn limits() -> RuntimeLimits {
    RuntimeLimits {
        max_rounds: 8,
        max_handoffs: 2,
        deadline_tick: 100,
    }
}
fn policies() -> Policies {
    Policies {
        user: grant(),
        group: grant(),
        task: grant(),
        tool: grant(),
    }
}
fn runtime(mode: Mode) -> Runtime {
    Runtime::new(
        config(mode),
        &host(),
        members(),
        if mode == Mode::PerTask {
            Some("a")
        } else {
            None
        },
        limits(),
        0,
        0,
    )
    .unwrap()
}
fn node(id: &str, member: &str, deps: &[&str]) -> PlannedChild {
    PlannedChild {
        id: id.into(),
        parent_id: "root".into(),
        depth: 1,
        member_id: member.into(),
        grant: grant(),
        dependencies: set(deps),
    }
}
fn command(s: &HostSnapshot, id: &str, child: &str) -> Command {
    Command {
        id: id.into(),
        identity: s.identity.clone(),
        child_id: child.into(),
        payload_digest: format!("digest-{id}"),
        reservation: 5,
    }
}
fn origin() -> Origin {
    Origin::Coordinator {
        id: "a".into(),
        epoch: 1,
    }
}
fn check(
    r: &Runtime,
    s: &HostSnapshot,
    p: &[PlannedChild],
    c: &Command,
) -> std::result::Result<Decision, RuntimeError> {
    r.advise(s, p, &policies(), c, Origin::Host, 1)
}
fn completed(s: &mut HostSnapshot, id: &str, member: &str) -> Observation {
    let c = command(s, &format!("cmd-{id}"), id);
    let req = format!("req-{id}");
    s.children.push(LedgerChild {
        id: id.into(),
        parent_id: "root".into(),
        depth: 1,
        state: ChildState::Completed,
    });
    s.commands.push(CommandRecord {
        command: c,
        request_id: req.clone(),
        state: CommandState::Completed,
    });
    Observation {
        event_id: format!("ev-{id}"),
        sequence: 1,
        identity: s.identity.clone(),
        child_id: id.into(),
        member_id: member.into(),
        request_id: req,
        outcome: Outcome::Completed,
        artifact_refs: set(&[&format!("artifact-{id}")]),
        evidence: vec![],
    }
}
fn evidence(stance: Stance, origin: &str) -> Evidence {
    Evidence {
        claim_id: "claim".into(),
        source_ref: "source".into(),
        source_version: "v1".into(),
        primary_origin: origin.into(),
        observed_at: 7,
        stance,
    }
}
#[test]
fn explicit_modes_choose_task_leader_without_changing_default() {
    assert_eq!(runtime(Mode::HostOnly).leader(), None);
    assert_eq!(runtime(Mode::Fixed).leader(), Some("a"));
    assert_eq!(runtime(Mode::PerTask).leader(), Some("a"));
    assert_eq!(
        Runtime::new(
            config(Mode::PerTask),
            &host(),
            members(),
            None,
            limits(),
            0,
            0
        )
        .unwrap_err(),
        RuntimeError::InvalidConfig
    );
    assert!(Runtime::new(
        config(Mode::HostOnly),
        &host(),
        members(),
        Some("a"),
        limits(),
        0,
        0
    )
    .is_err());
    assert!(Runtime::new(
        config(Mode::Fixed),
        &host(),
        members(),
        Some("b"),
        limits(),
        0,
        0
    )
    .is_err());
    assert!(Runtime::new(
        config(Mode::PerTask),
        &host(),
        members(),
        Some("missing"),
        limits(),
        0,
        0
    )
    .is_err());
}
#[test]
fn all_modes_use_same_deterministic_host_gates() {
    let s = host();
    let p = vec![node("z", "b", &[]), node("a", "a", &[])];
    for mode in [Mode::HostOnly, Mode::Fixed, Mode::PerTask] {
        let r = runtime(mode);
        assert_eq!(
            check(&r, &s, &p, &command(&s, "cmd", "a")),
            Ok(Decision::Eligible {
                child_id: "a".into()
            })
        );
        assert_eq!(
            check(&r, &s, &p, &command(&s, "cmd", "z")),
            Err(RuntimeError::Governance(Error::NotNextReady))
        );
    }
}
#[test]
fn coordinator_cannot_manage_and_wrong_leader_cannot_propose() {
    let s = host();
    let r = runtime(Mode::Fixed);
    let p = [node("a", "a", &[])];
    let c = command(&s, "cmd", "a");
    assert!(r
        .advise(
            &s,
            &p,
            &policies(),
            &c,
            Origin::Coordinator {
                id: "b".into(),
                epoch: 1
            },
            1
        )
        .is_err());
    assert!(r
        .advise(
            &s,
            &p,
            &policies(),
            &c,
            Origin::Coordinator {
                id: "a".into(),
                epoch: 2
            },
            1
        )
        .is_err());
    assert!(r.advise(&s, &p, &policies(), &c, origin(), 1).is_ok());
    assert!(validate_narrowing(
        &config(Mode::Fixed),
        &Principal::Member("a".into()),
        &grant(),
        &grant()
    )
    .is_err());
    assert!(runtime(Mode::HostOnly)
        .advise(&s, &p, &policies(), &c, origin(), 1)
        .is_err());
}
#[test]
fn scopes_budget_rounds_capacity_and_dag_are_not_bypassed() {
    let mut s = host();
    let r = runtime(Mode::PerTask);
    let p = [node("a", "a", &[])];
    let c = command(&s, "cmd", "a");
    let mut policy = policies();
    policy.tool.scopes.clear();
    assert_eq!(
        r.advise(&s, &p, &policy, &c, origin(), 1),
        Err(RuntimeError::Governance(Error::ScopeDenied))
    );
    s.budget.reserved = 96;
    assert_eq!(
        check(&r, &s, &p, &c),
        Err(RuntimeError::Governance(Error::BudgetLimit))
    );
    s = host();
    for id in ["x", "y"] {
        s.children.push(LedgerChild {
            id: id.into(),
            parent_id: "root".into(),
            depth: 1,
            state: ChildState::Running,
        });
    }
    assert_eq!(
        check(&r, &s, &p, &c),
        Err(RuntimeError::Governance(Error::ActiveLimit))
    );
    s = host();
    assert_eq!(
        check(&r, &s, &[node("a", "a", &["a"])], &c),
        Err(RuntimeError::Governance(Error::InvalidPlan))
    );
}
#[test]
fn stopped_and_deadline_preserve_lookup_without_dispatch() {
    let mut s = host();
    let mut r = runtime(Mode::Fixed);
    let c = command(&s, "cmd", "a");
    let p = [node("a", "a", &[])];
    s.commands.push(CommandRecord {
        command: c.clone(),
        request_id: "original".into(),
        state: CommandState::Unknown,
    });
    s.budget.unknown_request_ids.insert("original".into());
    let before = s.clone();
    r.stop();
    assert_eq!(
        check(&r, &s, &p, &c),
        Ok(Decision::LookupOriginal {
            request_id: "original".into(),
            state: CommandState::Unknown
        })
    );
    assert_eq!(
        check(&r, &s, &p, &command(&s, "new", "a")),
        Err(RuntimeError::Stopped)
    );
    assert_eq!(s, before);
    let s = host();
    assert_eq!(
        runtime(Mode::Fixed).advise(&s, &p, &policies(), &c, Origin::Host, 100),
        Err(RuntimeError::Deadline)
    );
}
#[test]
fn unknown_submitted_prepared_and_child_unknown_gate_handoff_and_new_work() {
    for state in [
        CommandState::Unknown,
        CommandState::Submitted,
        CommandState::Prepared,
    ] {
        let mut s = host();
        let mut r = runtime(Mode::PerTask);
        let c = command(&s, "old", "x");
        s.commands.push(CommandRecord {
            command: c,
            request_id: "original".into(),
            state,
        });
        assert!(r
            .handoff(
                &s,
                &Principal::Human("owner".into()),
                "b",
                &policies(),
                &[],
                1
            )
            .is_err());
        assert_eq!(
            check(&r, &s, &[node("a", "a", &[])], &command(&s, "new", "a")),
            Err(RuntimeError::ReconcileOriginal)
        );
    }
    let mut s = host();
    s.children.push(LedgerChild {
        id: "x".into(),
        parent_id: "root".into(),
        depth: 1,
        state: ChildState::Unknown,
    });
    assert!(check(
        &runtime(Mode::Fixed),
        &s,
        &[node("a", "a", &[])],
        &command(&s, "new", "a")
    )
    .is_err());
}
#[test]
fn handoff_epoch_is_bounded_atomic_and_permissions_only_narrow() {
    let mut s = host();
    let mut r = runtime(Mode::PerTask);
    let before = s.clone();
    assert!(r
        .handoff(&s, &Principal::Member("a".into()), "b", &policies(), &[], 1)
        .is_err());
    assert_eq!(r.epoch(), 1);
    let m = MaterialRef {
        scope_id: "project:a".into(),
        source_id: "pdf".into(),
        version: "v1".into(),
    };
    let package = r
        .handoff(
            &s,
            &Principal::Human("admin".into()),
            "b",
            &policies(),
            std::slice::from_ref(&m),
            1,
        )
        .unwrap();
    assert_eq!(r.epoch(), 2);
    assert_eq!(r.leader(), Some("b"));
    assert_eq!(package.identity.coordinator_epoch, 2);
    assert_eq!(package.materials, vec![m]);
    assert_eq!(package.grant, grant());
    assert_eq!(s, before);
    assert_eq!(
        check(&r, &s, &[node("a", "a", &[])], &command(&s, "cmd", "a")),
        Err(RuntimeError::StaleIdentity)
    );
    s.identity.coordinator_epoch = 2;
    assert!(check(&r, &s, &[node("a", "a", &[])], &command(&s, "cmd", "a")).is_ok());
    assert!(r
        .advise(
            &s,
            &[node("a", "a", &[])],
            &policies(),
            &command(&s, "cmd", "a"),
            origin(),
            1
        )
        .is_err());
    r.handoff(
        &s,
        &Principal::Human("owner".into()),
        "a",
        &policies(),
        &[],
        1,
    )
    .unwrap();
    s.identity.coordinator_epoch = 3;
    assert_eq!(
        r.handoff(
            &s,
            &Principal::Human("owner".into()),
            "b",
            &policies(),
            &[],
            1
        ),
        Err(RuntimeError::HandoffLimit)
    );
}
#[test]
fn handoff_rejects_active_fixed_stopped_and_cross_scope_materials() {
    for state in [
        ChildState::Queued,
        ChildState::Running,
        ChildState::WaitingConfirmation,
        ChildState::Unknown,
    ] {
        let mut s = host();
        s.children.push(LedgerChild {
            id: "x".into(),
            parent_id: "root".into(),
            depth: 1,
            state,
        });
        assert!(runtime(Mode::PerTask)
            .handoff(
                &s,
                &Principal::Human("owner".into()),
                "b",
                &policies(),
                &[],
                1
            )
            .is_err());
    }
    assert!(runtime(Mode::Fixed)
        .handoff(
            &host(),
            &Principal::Human("owner".into()),
            "b",
            &policies(),
            &[],
            1
        )
        .is_err());
    let mut r = runtime(Mode::PerTask);
    let m = MaterialRef {
        scope_id: "project:secret".into(),
        source_id: "pdf".into(),
        version: "v1".into(),
    };
    assert!(r
        .handoff(
            &host(),
            &Principal::Human("owner".into()),
            "b",
            &policies(),
            &[m],
            1
        )
        .is_err());
    assert_eq!(r.epoch(), 1);
    r.stop();
    assert!(r
        .handoff(
            &host(),
            &Principal::Human("owner".into()),
            "b",
            &policies(),
            &[],
            1
        )
        .is_err());
}
#[test]
fn parallel_results_keep_dissent_and_deduplicate_primary_sources() {
    let mut s = host();
    let mut a = completed(&mut s, "x", "a");
    let mut b = completed(&mut s, "y", "b");
    a.evidence = vec![evidence(Stance::Supports, "origin1")];
    b.evidence = vec![evidence(Stance::Contradicts, "origin2")];
    let mut r = runtime(Mode::Fixed);
    r.collect(&s, &[node("x", "a", &[]), node("y", "b", &[])], b.clone())
        .unwrap();
    r.collect(&s, &[node("x", "a", &[]), node("y", "b", &[])], a.clone())
        .unwrap();
    let summary = r.summary();
    assert_eq!(summary.completed, set(&["x", "y"]));
    assert!(summary.claims["claim"].disputed);
    assert_eq!(
        summary.claims["claim"].independent_origins,
        set(&["origin1", "origin2"])
    );
    assert_eq!(
        r.collect(&s, &[node("x", "a", &[])], a.clone()),
        Ok(Collection::Duplicate)
    );
    let mut replay = a;
    replay.artifact_refs = set(&["replacement"]);
    assert_eq!(
        r.collect(&s, &[node("x", "a", &[])], replay),
        Err(RuntimeError::EventConflict)
    );
    let mut r = runtime(Mode::HostOnly);
    a = completed(&mut host(), "x", "a");
    a.evidence = vec![
        evidence(Stance::Supports, "same"),
        evidence(Stance::Supports, "same"),
    ];
    r.collect(&s, &[node("x", "a", &[])], a).unwrap();
    assert_eq!(r.summary().claims["claim"].independent_origins.len(), 1);
}
#[test]
fn result_requires_original_host_receipt_artifact_and_matching_member() {
    let mut s = host();
    let a = completed(&mut s, "x", "a");
    let p = [node("x", "a", &[])];
    let mut bad = a.clone();
    bad.member_id = "b".into();
    assert!(runtime(Mode::Fixed).collect(&s, &p, bad).is_err());
    let mut bad = a.clone();
    bad.artifact_refs.clear();
    assert!(runtime(Mode::Fixed).collect(&s, &p, bad).is_err());
    let mut bad = a.clone();
    bad.request_id = "fake".into();
    assert!(runtime(Mode::Fixed).collect(&s, &p, bad).is_err());
    s.commands[0].state = CommandState::Submitted;
    assert!(runtime(Mode::Fixed).collect(&s, &p, a).is_err());
}
#[test]
fn unknown_can_resolve_only_with_new_original_receipt_event() {
    let mut s = host();
    let mut a = completed(&mut s, "x", "a");
    a.outcome = Outcome::Unknown;
    a.artifact_refs.clear();
    s.children[0].state = ChildState::Unknown;
    s.commands[0].state = CommandState::Unknown;
    let p = [node("x", "a", &[])];
    let mut r = runtime(Mode::Fixed);
    r.collect(&s, &p, a.clone()).unwrap();
    assert_eq!(r.summary().unknown, set(&["x"]));
    let mut done = a.clone();
    done.sequence = 2;
    done.event_id = "resolved".into();
    done.outcome = Outcome::Completed;
    done.artifact_refs = set(&["artifact"]);
    assert!(r.collect(&s, &p, done.clone()).is_err());
    s.children[0].state = ChildState::Completed;
    s.commands[0].state = CommandState::Completed;
    r.collect(&s, &p, done).unwrap();
    assert!(r.summary().unknown.is_empty());
    assert_eq!(r.summary().completed, set(&["x"]));
    assert_eq!(r.collect(&s, &p, a), Err(RuntimeError::InvalidResult));
}
#[test]
fn stale_epoch_results_are_archived_and_original_lookup_survives_handoff() {
    let mut s = host();
    let a = completed(&mut s, "x", "a");
    let c = s.commands[0].command.clone();
    let mut r = runtime(Mode::PerTask);
    r.handoff(
        &s,
        &Principal::Human("owner".into()),
        "b",
        &policies(),
        &[],
        1,
    )
    .unwrap();
    s.identity.coordinator_epoch = 2;
    assert_eq!(
        r.collect(&s, &[node("x", "a", &[])], a),
        Ok(Collection::LateEvidence)
    );
    assert!(r.summary().completed.is_empty());
    assert_eq!(r.late_evidence().len(), 1);
    assert_eq!(
        r.lookup_original(&s, &c),
        Ok(Some(Decision::LookupOriginal {
            request_id: "req-x".into(),
            state: CommandState::Completed
        }))
    );
}
#[test]
fn restored_limits_and_snapshot_fences_fail_closed() {
    let mut s = host();
    let mut l = limits();
    l.max_rounds = 0;
    assert!(Runtime::new(config(Mode::HostOnly), &s, members(), None, l, 0, 0).is_err());
    assert!(Runtime::new(
        config(Mode::HostOnly),
        &s,
        members(),
        None,
        limits(),
        100,
        0
    )
    .is_err());
    assert!(Runtime::new(
        config(Mode::PerTask),
        &s,
        members(),
        Some("a"),
        limits(),
        0,
        3
    )
    .is_err());
    s.identity.coordinator_epoch = u64::MAX;
    let mut r = Runtime::new(
        config(Mode::PerTask),
        &s,
        members(),
        Some("a"),
        limits(),
        0,
        0,
    )
    .unwrap();
    assert_eq!(
        r.handoff(
            &s,
            &Principal::Human("owner".into()),
            "b",
            &policies(),
            &[],
            1
        ),
        Err(RuntimeError::EpochExhausted)
    );
    assert_eq!(r.epoch(), u64::MAX);
    let mut s = host();
    s.identity.owner_epoch = "other".into();
    assert_eq!(
        check(
            &runtime(Mode::Fixed),
            &s,
            &[node("a", "a", &[])],
            &command(&s, "cmd", "a")
        ),
        Err(RuntimeError::StaleIdentity)
    );
}

#[test]
fn scheduling_projection_preserves_unknown_hold_and_stop_is_monotonic() {
    let mut s = host();
    let mut r = runtime(Mode::HostOnly);
    assert_eq!(
        r.status(&s, 1).unwrap(),
        SchedulingState::Ready { available_slots: 2 }
    );
    s.budget.unknown_request_ids = set(&["original"]);
    assert_eq!(
        r.status(&s, 1).unwrap(),
        SchedulingState::Reconciling {
            request_ids: set(&["original"])
        }
    );
    let held = s.budget.clone();
    r.stop();
    assert_eq!(r.status(&s, 101).unwrap(), SchedulingState::Stopped);
    assert_eq!(s.budget, held);
    let mut s = host();
    s.stopped = true;
    let r = Runtime::new(config(Mode::HostOnly), &s, members(), None, limits(), 0, 0).unwrap();
    s.stopped = false;
    assert_eq!(r.status(&s, 1).unwrap(), SchedulingState::Stopped);
}
#[test]
fn summaries_keep_artifact_and_speaker_attribution_and_failures() {
    let mut s = host();
    let a = completed(&mut s, "x", "a");
    let mut b = completed(&mut s, "y", "b");
    b.outcome = Outcome::Failed;
    b.artifact_refs.clear();
    s.children[1].state = ChildState::Failed;
    s.commands[1].state = CommandState::Failed;
    let mut r = runtime(Mode::Fixed);
    let p = [node("x", "a", &[]), node("y", "b", &[])];
    r.collect(&s, &p, a.clone()).unwrap();
    r.collect(&s, &p, b.clone()).unwrap();
    assert_eq!(r.summary().results["x"], a);
    assert_eq!(r.summary().results["y"], b);
    assert_eq!(r.summary().failed, set(&["y"]));
}
#[test]
fn projection_and_advice_share_round_budget_and_capacity_boundaries() {
    let mut s = host();
    let mut l = limits();
    l.max_rounds = 1;
    let r = Runtime::new(config(Mode::HostOnly), &s, members(), None, l, 0, 0).unwrap();
    completed(&mut s, "x", "a");
    assert_eq!(r.status(&s, 1).unwrap(), SchedulingState::RoundLimit);
    assert_eq!(
        check(&r, &s, &[node("a", "a", &[])], &command(&s, "new", "a")),
        Err(RuntimeError::Governance(Error::RoundLimit))
    );
    s = host();
    s.budget.known_actual = u64::MAX;
    assert_eq!(
        runtime(Mode::HostOnly).status(&s, 1).unwrap(),
        SchedulingState::BudgetLimit
    );
    s = host();
    for id in ["x", "y"] {
        s.children.push(LedgerChild {
            id: id.into(),
            parent_id: "root".into(),
            depth: 1,
            state: ChildState::Running,
        });
    }
    assert_eq!(
        runtime(Mode::HostOnly).status(&s, 1).unwrap(),
        SchedulingState::Ready { available_slots: 0 }
    );
}
#[test]
fn handoff_does_not_restore_permissions_when_returning_to_previous_leader() {
    let mut s = host();
    let mut ms = members();
    ms[0].grant.scopes.insert("project:extra".into());
    let mut ps = policies();
    ps.user.scopes.insert("project:extra".into());
    ps.group = ps.user.clone();
    ps.task = ps.user.clone();
    ps.tool = ps.user.clone();
    let mut r = Runtime::new(config(Mode::PerTask), &s, ms, Some("a"), limits(), 0, 0).unwrap();
    let first = r
        .handoff(&s, &Principal::Human("owner".into()), "b", &ps, &[], 1)
        .unwrap();
    assert_eq!(first.grant, grant());
    s.identity.coordinator_epoch = 2;
    let second = r
        .handoff(&s, &Principal::Human("owner".into()), "a", &ps, &[], 1)
        .unwrap();
    assert_eq!(second.grant, grant());
}
#[test]
fn second_parallel_advice_requires_updated_authoritative_ledger() {
    let mut s = host();
    let r = runtime(Mode::HostOnly);
    let p = [node("a", "a", &[]), node("b", "b", &[])];
    assert!(check(&r, &s, &p, &command(&s, "cmd-a", "a")).is_ok());
    assert_eq!(
        check(&r, &s, &p, &command(&s, "cmd-b", "b")),
        Err(RuntimeError::Governance(Error::NotNextReady))
    );
    let mut receipt = completed(&mut s, "a", "a");
    receipt.outcome = Outcome::Unknown; // fixture does not invoke Agent
    s.children[0].state = ChildState::Running; // no terminal receipt yet => reconciliation blocks
    s.commands[0].state = CommandState::Submitted;
    assert_eq!(
        check(&r, &s, &[node("b", "b", &[])], &command(&s, "cmd-b", "b")),
        Err(RuntimeError::ReconcileOriginal)
    );
    // Original host has a known acknowledgement for a still-running child. The
    // command receipt is resolved but the child occupies a slot; b may be advised.
    s.commands[0].state = CommandState::Completed;
    assert!(check(&r, &s, &[node("b", "b", &[])], &command(&s, "cmd-b", "b")).is_ok());
}

#[test]
fn unknown_resolution_keeps_earlier_dissent_and_source_versions() {
    let mut s = host();
    let mut unknown = completed(&mut s, "x", "a");
    unknown.outcome = Outcome::Unknown;
    unknown.artifact_refs.clear();
    unknown.evidence = vec![evidence(Stance::Contradicts, "original")];
    s.children[0].state = ChildState::Unknown;
    s.commands[0].state = CommandState::Unknown;
    let p = [node("x", "a", &[])];
    let mut r = runtime(Mode::Fixed);
    r.collect(&s, &p, unknown.clone()).unwrap();
    let mut resolved = unknown;
    resolved.event_id = "resolved-event".into();
    resolved.sequence = 2;
    resolved.outcome = Outcome::Completed;
    resolved.artifact_refs = set(&["artifact"]);
    resolved.evidence = vec![evidence(Stance::Supports, "other")];
    resolved.evidence[0].source_version = "v2".into();
    s.children[0].state = ChildState::Completed;
    s.commands[0].state = CommandState::Completed;
    r.collect(&s, &p, resolved).unwrap();
    let summary = r.summary();
    assert!(summary.claims["claim"].disputed);
    assert_eq!(summary.claims["claim"].evidence.len(), 2);
    assert!(summary.unknown.is_empty());
    assert_eq!(summary.completed, set(&["x"]));
}

#[test]
fn exact_budget_allows_zero_reservation_without_hiding_unknown_usage() {
    let mut s = host();
    s.budget.ceiling = s.budget.known_actual + s.budget.reserved;
    let r = runtime(Mode::HostOnly);
    assert_eq!(
        r.status(&s, 1).unwrap(),
        SchedulingState::Ready { available_slots: 2 }
    );
    let mut c = command(&s, "zero-reservation", "a");
    c.reservation = 0;
    assert!(check(&r, &s, &[node("a", "a", &[])], &c).is_ok());
    s.budget.unknown_request_ids.insert("missing-usage".into());
    assert_eq!(
        check(&r, &s, &[node("a", "a", &[])], &c),
        Err(RuntimeError::ReconcileOriginal)
    );
}
