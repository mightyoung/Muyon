use hy_memory_governance_lab::*;
use std::path::Path;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let mut lab = Lab::open(Path::new(&a[1])).unwrap();
    if a[2] == "verify" {
        assert!(lab.current("m").is_err());
        return;
    }
    if a[2] == "work" {
        lab.work("r", "vector", 100, "done", Crash::AfterSink)
            .unwrap();
    } else {
        let member = lab.current("m").unwrap();
        let d = Delete {
            request: "r".into(),
            member,
            purpose: "manage".into(),
        };
        lab.delete(
            &d,
            if a[2] == "before" {
                Crash::BeforeCommit
            } else {
                Crash::AfterCommit
            },
        )
        .unwrap();
    }
}
