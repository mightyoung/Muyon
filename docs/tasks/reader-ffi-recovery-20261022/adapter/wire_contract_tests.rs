#[path = "reader_policy_bindings.rs"]
mod wire;
use wire::*;
fn scope() -> ScopeCorrelation {
    ScopeCorrelation {
        service_session: "original-session".into(),
        generation: "scope-generation".into(),
        project: "selected-project".into(),
    }
}
fn key(kind: OriginalKind) -> OriginalKey {
    OriginalKey {
        scope: scope(),
        kind,
        attempt_id: "original-attempt".into(),
    }
}
fn frame() -> FrameCorrelation {
    FrameCorrelation {
        scope: scope(),
        selection_epoch: "2".into(),
        presentation_id: "opaque-presentation".into(),
        frame_generation: "3".into(),
    }
}
#[test]
fn counters_accept_exact_u64_without_i64_or_jvm_long_narrowing() {
    assert_eq!(counter("0"), Ok(0));
    assert_eq!(counter("18446744073709551615"), Ok(u64::MAX));
    assert_eq!(counter("9223372036854775808"), Ok(1u64 << 63));
}
#[test]
fn counters_refuse_noncanonical_aliases_and_overflow() {
    for value in [
        "",
        "01",
        "+1",
        "00",
        " 1",
        "1 ",
        "-1",
        "1.0",
        "١",
        "18446744073709551616",
    ] {
        assert_eq!(counter(value), Err(InputError::Counter), "{value:?}");
    }
}
#[test]
fn identifiers_are_bounded_ascii_without_paths_or_nul() {
    for value in [
        "",
        "a/b",
        "../relative",
        "x\\y",
        "x\0y",
        "汉字",
        &"a".repeat(129),
    ] {
        assert_eq!(identifier(value), Err(InputError::Identifier));
    }
    assert!(identifier("native-ID_1.2:3").is_ok());
}
#[test]
fn exact_originals_do_not_cross_kind_scope_or_attempt() {
    let original = key(OriginalKind::Renew);
    assert!(original.check_same_original(&original.clone()).is_ok());
    for kind in [
        OriginalKind::Admission,
        OriginalKind::Begin,
        OriginalKind::Handoff,
        OriginalKind::Stop,
    ] {
        assert_eq!(
            original.check_same_original(&key(kind)),
            Err(InputError::Kind)
        );
    }
    let mut wrong = original.clone();
    wrong.attempt_id = "another-attempt".into();
    assert_eq!(
        original.check_same_original(&wrong),
        Err(InputError::Attempt)
    );
    for field in 0..3 {
        let mut wrong = original.clone();
        match field {
            0 => wrong.scope.service_session = "other-session".into(),
            1 => wrong.scope.generation = "other-generation".into(),
            _ => wrong.scope.project = "other-project".into(),
        }
        assert_eq!(original.check_same_original(&wrong), Err(InputError::Scope));
    }
}
#[test]
fn zero_and_noncanonical_frame_generations_are_not_current() {
    for value in ["0", "03", "+3"] {
        let mut wrong = frame();
        wrong.frame_generation = value.into();
        assert_eq!(wrong.validate(), Err(InputError::Counter));
    }
}
#[test]
fn old_callback_cannot_upgrade_or_mutate_newer_frame() {
    let current = frame();
    let before = current.clone();
    let mut old = current.clone();
    old.frame_generation = "2".into();
    assert_eq!(
        current.check_original_callback(&old),
        Err(InputError::Frame)
    );
    assert_eq!(current, before);
    assert!(current.check_original_callback(&current.clone()).is_ok());
}
#[test]
fn selection_aba_and_scope_changes_are_independent_fences() {
    let current = frame();
    let mut old = current.clone();
    old.selection_epoch = "1".into();
    assert_eq!(
        current.check_original_callback(&old),
        Err(InputError::Selection)
    );
    let mut old = current.clone();
    old.scope.generation = "old-scope".into();
    assert_eq!(
        current.check_original_callback(&old),
        Err(InputError::Scope)
    );
    let mut old = current.clone();
    old.presentation_id = "predecessor-only".into();
    assert_eq!(
        current.check_original_callback(&old),
        Err(InputError::Frame)
    );
}
#[test]
fn malformed_callback_cannot_be_equal_by_normalization() {
    let current = frame();
    let mut malformed = current.clone();
    malformed.frame_generation = "03".into();
    assert_eq!(
        current.check_original_callback(&malformed),
        Err(InputError::Counter)
    );
}
