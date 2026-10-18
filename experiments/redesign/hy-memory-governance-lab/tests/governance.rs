use hy_memory_governance_lab::*;
use std::{
    path::PathBuf,
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
};
static N: AtomicU64 = AtomicU64::new(0);
fn setup() -> (PathBuf, Lab, Member) {
    let p = std::env::temp_dir().join(format!(
        "hy-governance-{}-{}.db",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    let mut l = Lab::open(&p).unwrap();
    let m = l
        .seed("m", "合成🙂 secret tail")
        .expect("synthetic seed must persist");
    (p, l, m)
}
fn deletion(m: &Member) -> Delete {
    Delete {
        request: "r".into(),
        member: m.clone(),
        purpose: "manage".into(),
    }
}
fn child(p: &PathBuf, stage: &str) -> std::process::ExitStatus {
    Command::new(env!("CARGO_BIN_EXE_crash-worker"))
        .arg(p)
        .arg(stage)
        .status()
        .unwrap()
}
#[test]
fn atomic_precommit_crash_rolls_back_tombstone_and_outbox() {
    let (p, l, m) = setup();
    drop(l);
    assert_eq!(child(&p, "before").code(), Some(71));
    let l = Lab::open(&p).unwrap();
    assert_eq!(l.current("m"), Ok(m));
    assert!(l.jobs("r").unwrap().is_empty());
}
#[test]
fn commit_crash_reopens_in_other_process_and_blocks_read() {
    let (p, l, _) = setup();
    drop(l);
    assert_eq!(child(&p, "after").code(), Some(72));
    assert!(child(&p, "verify").success());
    let l = Lab::open(&p).unwrap();
    assert_eq!(l.current("m"), Err(Error::Denied));
    assert_eq!(l.jobs("r").unwrap().len(), 3);
}
#[test]
fn replay_is_bound_to_complete_payload() {
    let (_, mut l, m) = setup();
    let d = deletion(&m);
    let receipt = l.delete(&d, Crash::None).unwrap();
    assert_eq!(l.delete(&d, Crash::None).unwrap(), receipt);
    let mut altered = d.clone();
    altered.purpose = "other".into();
    assert_eq!(l.delete(&altered, Crash::None), Err(Error::Conflict));
    assert_eq!(l.jobs("r").unwrap().len(), 3);
}
#[test]
fn stale_delete_has_no_half_writes() {
    for field in [
        "revision",
        "source_revision",
        "authority",
        "policy",
        "digest",
        "revoked",
        "unknown",
    ] {
        let (_, mut l, m) = setup();
        l.change("m", field).unwrap();
        assert!(l.delete(&deletion(&m), Crash::None).is_err(), "{field}");
        assert!(l.jobs("r").unwrap().is_empty());
    }
}
#[test]
fn delete_management_survives_automatic_memory_switch_closed() {
    let (_, mut l, _) = setup();
    l.change("m", "automatic_closed").unwrap();
    let m = l.current("m").unwrap();
    l.delete(&deletion(&m), Crash::None).unwrap();
    assert_eq!(l.current("m"), Err(Error::Denied));
}
#[test]
fn cleanup_crash_retries_same_operation_after_lease_expiry() {
    let (p, mut l, m) = setup();
    l.delete(&deletion(&m), Crash::None).unwrap();
    drop(l);
    assert_eq!(child(&p, "work").code(), Some(73));
    let mut l = Lab::open(&p).unwrap();
    assert!(!l.sink_exists("m", "vector").unwrap());
    let j = l
        .jobs("r")
        .unwrap()
        .into_iter()
        .find(|j| j.sink == "vector")
        .unwrap();
    assert_eq!((j.status.as_str(), j.attempts), ("claimed", 1));
    assert_eq!(
        l.work("r", "vector", 105, "done", Crash::None),
        Err(Error::Denied)
    );
    l.work("r", "vector", 111, "done", Crash::None).unwrap();
    let k = l
        .jobs("r")
        .unwrap()
        .into_iter()
        .find(|j| j.sink == "vector")
        .unwrap();
    assert_eq!((k.status.as_str(), k.attempts), ("done", 2));
    assert_eq!(j.operation, k.operation);
    assert_eq!(l.current("m"), Err(Error::Denied));
}
#[test]
fn partial_failure_unknown_and_retry_are_persistent() {
    let (p, mut l, m) = setup();
    l.delete(&deletion(&m), Crash::None).unwrap();
    l.work("r", "vector", 10, "failed", Crash::None).unwrap();
    l.work("r", "cache", 10, "unknown", Crash::None).unwrap();
    drop(l);
    let mut l = Lab::open(&p).unwrap();
    let jobs = l.jobs("r").unwrap();
    assert!(jobs
        .iter()
        .any(|j| j.status == "failed" && j.attempts == 1 && j.next_retry == 20));
    assert!(jobs.iter().any(|j| j.status == "unknown"));
    assert_eq!(
        l.work("r", "vector", 11, "done", Crash::None),
        Err(Error::Denied)
    );
    l.work("r", "vector", 20, "failed", Crash::None).unwrap();
    l.work("r", "cache", 20, "done", Crash::None).unwrap();
    let jobs = l.jobs("r").unwrap();
    assert!(jobs.iter().any(|j| j.status == "failed" && j.attempts == 2));
    assert!(jobs.iter().any(|j| j.status == "done"));
    assert_eq!(l.current("missing"), Err(Error::Absent));
    l.change("m", "unknown").unwrap();
    assert_eq!(l.current("m"), Err(Error::Unknown));
}
#[test]
fn every_member_current_field_is_checked_at_final_consume() {
    for field in [
        "revision",
        "source_revision",
        "authority",
        "policy",
        "digest",
        "revoked",
        "tombstone",
        "disabled",
        "expired",
        "lineage",
        "scope",
        "uses",
        "memory_read_closed",
        "unknown",
    ] {
        let (_, mut l, m) = setup();
        let n = l.seed("n", "synthetic second").unwrap();
        l.change("n", field).unwrap();
        assert!(l.consume(&[m, n]).is_err(), "{field}");
        assert_eq!(l.consumed().unwrap(), 0);
    }
}
#[test]
fn revoke_before_consume_rejects_prebuilt_projection() {
    let (p, mut l, m) = setup();
    let ticket = vec![m];
    let mut other = Lab::open(&p).unwrap();
    other.change("m", "revoked").unwrap();
    assert_eq!(l.consume(&ticket), Err(Error::Denied));
    assert_eq!(l.consumed().unwrap(), 0);
}
#[test]
fn consume_before_revoke_is_recorded_but_future_consumption_denied() {
    let (p, mut l, m) = setup();
    l.consume(&[m.clone()]).unwrap();
    Lab::open(&p).unwrap().change("m", "revoked").unwrap();
    assert_eq!(l.consumed().unwrap(), 1);
    assert_eq!(l.consume(&[m]), Err(Error::Denied));
}
#[test]
fn utf8_ranges_and_redaction_do_not_forge_contiguous_quote() {
    let (_, mut l, m) = setup();
    let a = Segment {
        start: 0,
        end: 6,
        replacement: None,
    };
    assert_eq!(l.quote(&m, &[a.clone()], true).unwrap().display, "合成");
    for (start, end) in [(1, 6), (0, 999), (7, 10), (6, 5)] {
        assert_eq!(
            l.quote(
                &m,
                &[Segment {
                    start,
                    end,
                    replacement: None
                }],
                true
            ),
            Err(Error::InvalidSpan)
        );
    }
    let segments = vec![
        a,
        Segment {
            start: 6,
            end: 18,
            replacement: Some("sensitive".into()),
        },
        Segment {
            start: 18,
            end: 22,
            replacement: None,
        },
    ];
    assert_eq!(l.quote(&m, &segments, true), Err(Error::Redacted));
    assert_eq!(
        l.quote(&m, &segments, false).unwrap().display,
        "合成[redacted:sensitive]tail"
    );
}
#[test]
fn quotes_revalidate_source_identity_and_authority() {
    for field in [
        "source_revision",
        "digest",
        "revoked",
        "tombstone",
        "unknown",
    ] {
        let (_, mut l, m) = setup();
        l.change("m", field).unwrap();
        assert!(
            l.quote(
                &m,
                &[Segment {
                    start: 0,
                    end: 6,
                    replacement: None
                }],
                true
            )
            .is_err(),
            "{field}"
        );
    }
}
#[test]
fn redaction_reason_is_allowlisted_and_output_carries_marker() {
    let (_, mut l, m) = setup();
    let segment = Segment {
        start: 6,
        end: 18,
        replacement: Some("sensitive".into()),
    };
    assert_eq!(
        l.quote(&m, &[segment], false).unwrap().display,
        "[redacted:sensitive]"
    );
    let forged = Segment {
        start: 6,
        end: 18,
        replacement: Some("secret text".into()),
    };
    assert_eq!(l.quote(&m, &[forged], false), Err(Error::Redacted));
}
#[test]
fn revocation_transaction_holds_shared_fence_until_consume_can_validate() {
    use std::{sync::mpsc, thread, time::Duration};
    let (p, _, m) = setup();
    let writer = rusqlite::Connection::open(&p).unwrap();
    writer
        .execute_batch(
            "BEGIN IMMEDIATE; UPDATE memory SET tombstone=1,generation=generation+1 WHERE id='m';",
        )
        .unwrap();
    let (ready_tx, ready_rx) = mpsc::channel();
    let (done_tx, done_rx) = mpsc::channel();
    let t = thread::spawn(move || {
        let mut consumer = Lab::open(&p).unwrap();
        ready_tx.send(()).unwrap();
        let result = consumer.consume(&[m]);
        done_tx.send(result).unwrap();
    });
    ready_rx.recv_timeout(Duration::from_secs(2)).unwrap();
    assert!(
        done_rx.recv_timeout(Duration::from_millis(30)).is_err(),
        "consume must wait for governance transaction"
    );
    writer.execute_batch("COMMIT").unwrap();
    assert_eq!(
        done_rx.recv_timeout(Duration::from_secs(2)).unwrap(),
        Err(Error::Denied)
    );
    t.join().unwrap();
}
#[test]
fn automatic_write_control_is_independent_from_memory_read() {
    let (_, mut l, _) = setup();
    l.change("m", "automatic_closed").unwrap();
    let fresh = l.current("m").unwrap();
    l.consume(&[fresh])
        .expect("closed automatic writes still allow existing memory reads");
}
#[test]
fn cleanup_operation_identity_handles_colons_without_collision() {
    let (_, mut l, _) = setup();
    let a = l.seed("y", "synthetic a").unwrap();
    let b = l.seed("x:vector:y", "synthetic b").unwrap();
    let mut da = deletion(&a);
    da.request = "r:vector:x".into();
    let db = deletion(&b);
    l.delete(&da, Crash::None).unwrap();
    l.delete(&db, Crash::None)
        .expect("distinct deletion identities must not collide");
}
#[test]
fn all_controlled_sink_completion_removes_governed_body() {
    let (p, mut l, m) = setup();
    l.delete(&deletion(&m), Crash::None).unwrap();
    for job in l.jobs("r").unwrap() {
        l.work("r", &job.sink, 100, "done", Crash::None).unwrap();
    }
    let db = rusqlite::Connection::open(p).unwrap();
    let body: String = db
        .query_row("SELECT body FROM memory WHERE id='m'", [], |r| r.get(0))
        .unwrap();
    assert!(
        body.is_empty(),
        "all controlled sinks cannot be done while governed body remains"
    );
}
#[test]
fn stale_worker_acknowledgement_cannot_overwrite_new_claim_completion() {
    let (_, mut l, m) = setup();
    l.delete(&deletion(&m), Crash::None).unwrap();
    let a = l.claim("r", "vector", 10).unwrap().unwrap();
    let b = l.claim("r", "vector", 21).unwrap().unwrap();
    l.complete(&b, "done", Crash::None).unwrap();
    assert_eq!(l.complete(&a, "failed", Crash::None), Err(Error::Denied));
    let j = l
        .jobs("r")
        .unwrap()
        .into_iter()
        .find(|j| j.sink == "vector")
        .unwrap();
    assert_eq!(j.status, "done");
}
#[test]
fn quote_retains_source_identity_and_each_original_byte_range() {
    let (_, mut l, m) = setup();
    let q = l
        .quote(
            &m,
            &[Segment {
                start: 0,
                end: 6,
                replacement: None,
            }],
            true,
        )
        .unwrap();
    assert_eq!(q.source_id, "source:m");
    assert_eq!(q.source_revision, 1);
    assert!(!q.source_digest.is_empty());
    assert_eq!((q.segments[0].start, q.segments[0].end), (0, 6));
    assert!(!q.segments[0].redacted);
}
#[test]
fn independent_source_authority_and_memory_read_gates_block_current_tickets() {
    for condition in [
        "source_revoked",
        "source_tombstone",
        "source_unknown",
        "source_identity",
        "source_digest",
        "memory_read_closed",
    ] {
        let (_, mut l, m) = setup();
        let changed = l.change("m", condition);
        assert_eq!(
            changed,
            Ok(()),
            "fixture must independently vary {condition}"
        );
        assert!(l.consume(&[m]).is_err(), "{condition}");
    }
}
#[test]
fn body_forks_without_revision_change_are_not_consumed_or_quoted() {
    for table in ["memory", "sources"] {
        let (p, mut l, m) = setup();
        let db = rusqlite::Connection::open(&p).unwrap();
        db.execute(
            &format!("UPDATE {table} SET body='tampered synthetic body'"),
            [],
        )
        .unwrap();
        assert!(
            l.consume(&[m.clone()]).is_err(),
            "{table} byte fork must fail closed"
        );
        assert!(
            l.quote(
                &m,
                &[Segment {
                    start: 0,
                    end: 6,
                    replacement: None
                }],
                true
            )
            .is_err(),
            "{table}"
        );
    }
}
#[test]
fn independent_gate_facts_deny_even_without_generation_bump() {
    for sql in [
        "UPDATE memory SET memory_read=0",
        "UPDATE memory SET manager_allowed=0",
        "UPDATE memory SET disabled=1",
        "UPDATE memory SET expired=1",
        "UPDATE memory SET tombstone=1",
        "UPDATE memory SET scope='other'",
        "UPDATE memory SET allowed_uses='other'",
        "UPDATE memory SET lineage='other'",
        "UPDATE sources SET allowed=0",
        "UPDATE sources SET tombstone=1",
    ] {
        let (p, mut l, m) = setup();
        rusqlite::Connection::open(p)
            .unwrap()
            .execute(sql, [])
            .unwrap();
        assert!(l.consume(&[m]).is_err(), "{sql}");
    }
}
#[test]
fn actual_sqlite_read_error_and_missing_source_are_not_absent() {
    let (p, mut l, m) = setup();
    let db = rusqlite::Connection::open(p).unwrap();
    db.execute("DELETE FROM sources", []).unwrap();
    assert_eq!(l.current("m"), Err(Error::Unknown));
    assert_eq!(l.consume(&[m]), Err(Error::Unknown));
    db.execute("DROP TABLE memory", []).unwrap();
    assert_eq!(l.current("m"), Err(Error::Storage));
}
#[test]
fn deletion_explicitly_checks_current_tombstone_without_trusting_ticket_generation() {
    let (p, mut l, m) = setup();
    rusqlite::Connection::open(p)
        .unwrap()
        .execute("UPDATE memory SET tombstone=1", [])
        .unwrap();
    assert_eq!(l.delete(&deletion(&m), Crash::None), Err(Error::Denied));
    assert!(l.jobs("r").unwrap().is_empty());
}
