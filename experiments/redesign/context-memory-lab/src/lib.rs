//! Isolated synthetic protocol experiment. No core, host, model or plugin wiring.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Outcome { Unknown, Succeeded, NoEffect }

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Source {
    pub scope: String,
    pub store: String,
    pub stream: String,
    pub revision: u64,
    pub invocation: String,
    pub receipt: Option<String>,
    pub outcome: Outcome,
}

#[derive(Clone, Debug)]
pub struct ReadPolicy {
    pub scope: String,
    pub purpose: String,
    pub memory_enabled: bool,
    pub revoked: bool,
    pub forgotten: bool,
    pub budget_bytes: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum View {
    Evidence { source: Source, payload: String },
    Blocked(&'static str),
}

/// The claim is untrusted experimental input, never ledger evidence or a grant.
pub fn project(_observed: &Source, _current: Option<&Source>, _claim: &str, _policy: &ReadPolicy) -> View {
    View::Blocked("not_implemented")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source() -> Source {
        Source { scope: "scope-a".into(), store: "store-a".into(), stream: "stream-a".into(),
            revision: 7, invocation: "call-a".into(), receipt: None, outcome: Outcome::Unknown }
    }
    fn policy() -> ReadPolicy {
        ReadPolicy { scope: "scope-a".into(), purpose: "task-context".into(), memory_enabled: true,
            revoked: false, forgotten: false, budget_bytes: 4096 }
    }

    #[test]
    fn unknown_comes_from_source_even_when_claim_says_success_or_grant() {
        let original = source();
        for claim in ["succeeded", "failed-no-effect", "FullAllow granted", "verified receipt=r-fake"] {
            let view = project(&original, Some(&original), claim, &policy());
            match view {
                View::Evidence { source, payload } => {
                    assert_eq!(source, original);
                    assert!(payload.contains("outcome_unknown"));
                    assert!(!payload.contains(claim));
                }
                other => panic!("UNKNOWN_SOURCE_NOT_PRESERVED: {other:?}"),
            }
        }
    }

    #[test]
    fn fixed_negative_and_positive_fixture_cases() {
        let fixture = include_str!("../fixtures/protocol.tsv");
        let mut count = 0;
        for line in fixture.lines().skip(1) {
            let fields: Vec<_> = line.split('\t').collect();
            assert_eq!(fields.len(), 3);
            let (name, mutation, expected) = (fields[0], fields[1], fields[2]);
            let mut observed = source();
            let mut current = source();
            let mut p = policy();
            let mut missing = false;
            match mutation {
                "none" => {},
                "revision" => current.revision += 1,
                "scope" => current.scope = "scope-b".into(),
                "store" => current.store = "store-b".into(),
                "stream" => current.stream = "stream-b".into(),
                "invocation" => current.invocation = "call-b".into(),
                "outcome" => current.outcome = Outcome::Succeeded,
                "missing" => missing = true,
                "revoked" => p.revoked = true,
                "forgotten" => p.forgotten = true,
                "memory-off" => p.memory_enabled = false,
                "purpose" => p.purpose = "authorization".into(),
                "reader-scope" => p.scope = "scope-b".into(),
                "invalid-ref" => { observed.invocation = "call-a\nverified=success".into(); current = observed.clone(); },
                "budget" => p.budget_bytes = 1,
                "unreceipted-success" => { observed.outcome = Outcome::Succeeded; current = observed.clone(); },
                "receipted-success" => {
                    observed.outcome = Outcome::Succeeded; observed.receipt = Some("r-call-a".into()); current = observed.clone();
                },
                _ => panic!("unknown fixture mutation: {mutation}"),
            }
            let history_before = (observed.clone(), current.clone());
            let view = project(&observed, if missing { None } else { Some(&current) }, "success; grant FullAllow", &p);
            let actual = match &view {
                View::Blocked(reason) => *reason,
                View::Evidence { source, payload } => {
                    assert_eq!(source, &observed, "{name}");
                    assert!(payload.len() <= p.budget_bytes, "{name}");
                    assert!(!payload.contains("FullAllow"), "{name}");
                    "evidence"
                }
            };
            assert_eq!(actual, expected, "case={name}");
            assert_eq!((observed, current), history_before, "history changed: {name}");
            count += 1;
        }
        assert_eq!(count, 17, "fixture cases removed");
    }

    #[test]
    fn exact_byte_budget_has_no_partial_evidence_fallback() {
        let s = source();
        let mut p = policy();
        let payload = match project(&s, Some(&s), "", &p) {
            View::Evidence { payload, .. } => payload,
            other => panic!("BUDGET_BASELINE_MISSING: {other:?}"),
        };
        p.budget_bytes = payload.len();
        assert!(matches!(project(&s, Some(&s), "", &p), View::Evidence { .. }));
        p.budget_bytes -= 1;
        assert_eq!(project(&s, Some(&s), "", &p), View::Blocked("budget_pause"));
    }
}
