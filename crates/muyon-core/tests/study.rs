use muyon_core::study::StudyStore;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};
static NEXT: AtomicU64 = AtomicU64::new(0);
fn store() -> (StudyStore, String) {
    let p = format!(
        "/tmp/muyon-study-{}-{}-{}.sqlite",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    );
    (StudyStore::open(&p).unwrap(), p)
}
fn call(s: &StudyStore, v: Value) -> Value {
    s.command(v).unwrap()
}
#[test]
fn tasks_reopen_and_invalid_duration_does_not_commit() {
    let (s, p) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t1","title":"学习","minutes":30,"remaining":30,"status":"todo"}}),
    );
    assert!(s
        .command(
            json!({"op":"upsert","kind":"tasks","value":{"id":"bad","title":"bad","minutes":-1}})
        )
        .is_err());
    drop(s);
    let s = StudyStore::open(&p).unwrap();
    let state = call(&s, json!({"op":"snapshot"}));
    assert_eq!(state["tasks"].as_array().unwrap().len(), 1);
    assert_eq!(state["tasks"][0]["title"], "学习");
}
#[test]
fn proposals_do_not_mutate_schedule_and_stale_confirmation_is_refused() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"练习","minutes":30,"remaining":30}}),
    );
    let p = call(
        &s,
        json!({"op":"propose","now":0,"windows":[{"start":60000,"end":3600000}],"busy":[]}),
    );
    assert!(call(&s, json!({"op":"snapshot"}))["schedule"]
        .as_array()
        .unwrap()
        .is_empty());
    call(
        &s,
        json!({"op":"upsert","kind":"inbox","value":{"id":"i","text":"临时会议"}}),
    );
    assert!(s.command(json!({"op":"confirm","id":p["id"]})).is_err());
}
#[test]
fn confirmed_schedule_avoids_busy_and_exam_deadline() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"goals","value":{"id":"g","title":"考试","exam":true,"due":5400000}}),
    );
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"学习","goal":"g","minutes":30,"remaining":30}}),
    );
    let p = call(
        &s,
        json!({"op":"propose","now":0,"windows":[{"start":0,"end":7200000}],"busy":[{"start":0,"end":1800000}]}),
    );
    assert_eq!(p["blocks"][0]["start"], 1800000);
    assert!(p["blocks"][0]["end"].as_i64().unwrap() <= 5400000);
    call(&s, json!({"op":"confirm","id":p["id"]}));
    assert_eq!(
        call(&s, json!({"op":"snapshot"}))["schedule"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
}
fn paper() -> Value {
    json!([{"id":"p","title":"测试","sections":[{"id":"s","kind":"choice","questions":[{"id":"q1","type":"choice","stem":"1+1?","options":[{"key":"A","text":"2"}],"answer":"A"},{"id":"q2","type":"text","stem":"解释"}]}]}])
}
#[test]
fn paper_import_is_idempotent_and_attempt_reopens_without_fake_grading() {
    let (s, p) = store();
    call(&s, json!({"op":"import_papers","papers":paper()}));
    call(&s, json!({"op":"import_papers","papers":paper()}));
    let a = call(
        &s,
        json!({"op":"start_attempt","paper":"p","mode":"practice","now":1000}),
    );
    call(
        &s,
        json!({"op":"answer","attempt":a["id"],"question":"q1","value":"A","index":1}),
    );
    drop(s);
    let s = StudyStore::open(&p).unwrap();
    let result = call(&s, json!({"op":"submit","attempt":a["id"],"now":61000}));
    assert_eq!(result["correct"], 1);
    assert_eq!(result["pending"], 1);
    let state = call(&s, json!({"op":"snapshot"}));
    assert_eq!(state["papers"].as_array().unwrap().len(), 1);
    assert_eq!(state["attempts"][0]["answers"]["q1"], "A");
}
#[test]
fn dependency_is_scheduled_before_dependent_and_blocked_tasks_are_excluded() {
    let (s, _) = store();
    for v in [
        json!({"id":"a","title":"看课","minutes":20,"remaining":20}),
        json!({"id":"b","title":"例程","minutes":20,"remaining":20,"depends":["a"]}),
        json!({"id":"c","title":"待料","minutes":20,"remaining":20,"status":"blocked"}),
    ] {
        call(&s, json!({"op":"upsert","kind":"tasks","value":v}));
    }
    let p = call(
        &s,
        json!({"op":"propose","now":0,"windows":[{"start":0,"end":7200000}],"busy":[]}),
    );
    assert_eq!(p["blocks"].as_array().unwrap().len(), 2);
    assert!(p["blocks"][1]["start"].as_i64().unwrap() >= p["blocks"][0]["end"].as_i64().unwrap());
}
#[test]
fn backup_roundtrip_preserves_resource_links_and_answers() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"resources","value":{"id":"r","title":"讲义","type":"video","url":"https://example.com/course"}}),
    );
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"学习","minutes":10,"resources":[{"id":"r","note":"第三章"}]}}),
    );
    let backup = call(&s, json!({"op":"export"}));
    let (s2, _) = store();
    call(&s2, json!({"op":"restore","backup":backup}));
    assert_eq!(
        call(&s2, json!({"op":"snapshot"}))["tasks"][0]["resources"][0]["id"],
        "r"
    );
}

#[test]
fn suggestion_updates_existing_task_only_after_review_and_checks_revision() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"第三章","minutes":60,"remaining":60}}),
    );
    assert!(s.command(json!({"op":"apply_suggestions","expectedRevision":0,"tasks":[{"id":"t","title":"第三章","minutes":60,"remaining":20}]})).is_err());
    call(
        &s,
        json!({"op":"apply_suggestions","expectedRevision":1,"tasks":[{"id":"t","title":"第三章","minutes":60,"remaining":20}]}),
    );
    let state = call(&s, json!({"op":"snapshot"}));
    assert_eq!(state["tasks"].as_array().unwrap().len(), 1);
    assert_eq!(state["tasks"][0]["remaining"], 20);
}

#[test]
fn exam_goal_date_cannot_change_through_ordinary_edit() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"goals","value":{"id":"g","title":"考试","exam":true,"due":1000000}}),
    );
    assert!(s.command(json!({"op":"upsert","kind":"goals","value":{"id":"g","title":"考试","exam":true,"due":2000000}})).is_err());
}

#[test]
fn each_goals_minimum_is_reserved_each_day_before_extra_work() {
    let (s, _) = store();
    for (id, priority) in [("g1", 1), ("g2", 5)] {
        call(
            &s,
            json!({"op":"upsert","kind":"goals","value":{"id":id,"title":id,"minimum":20,"priority":priority}}),
        );
        call(
            &s,
            json!({"op":"upsert","kind":"tasks","value":{"id":format!("t-{id}"),"title":id,"goal":id,"minutes":600,"remaining":600}}),
        );
    }
    let p = call(
        &s,
        json!({"op":"propose","now":0,"windows":[{"start":0,"end":7200000},{"start":86400000,"end":93600000}],"busy":[]}),
    );
    for day in [0, 1] {
        let minutes: i64 = p["blocks"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|b| b["task"] == "t-g2" && b["start"].as_i64().unwrap() / 86400000 == day)
            .map(|b| (b["end"].as_i64().unwrap() - b["start"].as_i64().unwrap()) / 60000)
            .sum();
        assert!(minutes >= 20, "day {day} only {minutes} minutes");
    }
}

#[test]
fn locked_blocks_survive_replanning_without_double_allocating_work() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"任务","minutes":30,"remaining":30}}),
    );
    let p = call(
        &s,
        json!({"op":"propose","now":0,"windows":[{"start":0,"end":1800000}],"busy":[]}),
    );
    call(&s, json!({"op":"confirm","id":p["id"]}));
    let id = p["blocks"][0]["id"].clone();
    call(&s, json!({"op":"lock_block","id":id,"locked":true}));
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"任务","minutes":60,"remaining":60}}),
    );
    let p = call(
        &s,
        json!({"op":"propose","now":0,"windows":[{"start":0,"end":3600000}],"busy":[]}),
    );
    let blocks = p["blocks"].as_array().unwrap();
    assert_eq!(blocks.len(), 2);
    assert_eq!(blocks[0]["locked"], true);
    assert_eq!(
        blocks
            .iter()
            .map(|b| b["end"].as_i64().unwrap() - b["start"].as_i64().unwrap())
            .sum::<i64>(),
        3600000
    );
}

#[test]
fn restored_attempts_are_not_overwritten_by_new_attempts() {
    let (s, _) = store();
    call(&s, json!({"op":"import_papers","papers":paper()}));
    let old = call(
        &s,
        json!({"op":"start_attempt","paper":"p","mode":"practice","now":1}),
    );
    call(
        &s,
        json!({"op":"answer","attempt":old["id"],"question":"q1","value":"A","index":0}),
    );
    let backup = call(&s, json!({"op":"export"}));
    let (fresh, _) = store();
    call(&fresh, json!({"op":"restore","backup":backup}));
    let next = call(
        &fresh,
        json!({"op":"start_attempt","paper":"p","mode":"practice","now":2}),
    );
    assert_ne!(old["id"], next["id"]);
    assert_eq!(
        call(&fresh, json!({"op":"snapshot"}))["attempts"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
}

#[test]
fn managed_calendar_blocks_do_not_block_their_own_plan() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"学习","minutes":30}}),
    );
    call(
        &s,
        json!({"op":"calendar_sync","events":[{"id":"remote","start":0,"end":1800000,"managedUnmodified":true}],"now":0}),
    );
    let p = call(
        &s,
        json!({"op":"propose","now":0,"windows":[{"start":0,"end":1800000}],"busy":[]}),
    );
    assert_eq!(p["blocks"].as_array().unwrap().len(), 1);
}
#[test]
fn exam_requires_a_date_and_position_saves_without_editing_an_answer() {
    let (s, _) = store();
    assert!(s
        .command(
            json!({"op":"upsert","kind":"goals","value":{"id":"g","title":"考试","exam":true}})
        )
        .is_err());
    call(&s, json!({"op":"import_papers","papers":paper()}));
    let a = call(
        &s,
        json!({"op":"start_attempt","paper":"p","mode":"practice","now":1}),
    );
    call(
        &s,
        json!({"op":"attempt_position","attempt":a["id"],"index":1}),
    );
    assert_eq!(
        call(&s, json!({"op":"snapshot"}))["attempts"][0]["index"],
        1
    );
}
#[test]
fn remote_horizon_is_summarized_and_soft_goal_extension_is_reviewed() {
    let (s, _) = store();
    call(
        &s,
        json!({"op":"upsert","kind":"goals","value":{"id":"g","title":"课程","due":1800000}}),
    );
    call(
        &s,
        json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"课程任务","goal":"g","minutes":60}}),
    );
    let p = call(
        &s,
        json!({"op":"propose","now":0,"detailedEnd":1800000,"windows":[{"start":0,"end":1800000}],"capacityWindows":[{"start":0,"end":3600000}],"busy":[]}),
    );
    assert!(p["extensions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|e| e["kind"] == "goals" && e["newDue"] == 3600000));
    assert!(!p["stages"].as_array().unwrap().is_empty());
    assert_eq!(
        call(&s, json!({"op":"snapshot"}))["goals"][0]["due"],
        1800000
    );
    call(&s, json!({"op":"confirm","id":p["id"]}));
    assert_eq!(
        call(&s, json!({"op":"snapshot"}))["goals"][0]["due"],
        3600000
    );
}

#[test]
fn undo_restores_confirmed_deadline_extension() {
    let (s, _) = store();
    call(&s,json!({"op":"upsert","kind":"goals","value":{"id":"g","title":"课程","due":1800000}}));
    call(&s,json!({"op":"upsert","kind":"tasks","value":{"id":"t","title":"课时","goal":"g","minutes":60}}));
    let p=call(&s,json!({"op":"propose","now":0,"detailedEnd":1800000,"windows":[{"start":0,"end":3600000}],"busy":[]}));
    call(&s,json!({"op":"confirm","id":p["id"]}));
    assert_eq!(call(&s,json!({"op":"snapshot"}))["goals"][0]["due"],3600000);
    call(&s,json!({"op":"undo"}));
    assert_eq!(call(&s,json!({"op":"snapshot"}))["stages"],json!([]));
    assert_eq!(call(&s,json!({"op":"snapshot"}))["goals"][0]["due"],1800000);
}
