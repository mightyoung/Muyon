#[test]
fn native_host_executes_registered_read() {
    let observed = muyon_rust_agent_host_lab::native_read_probe();
    assert!(matches!(observed, Ok(_) | Err(muyon_rust_agent_host_lab::STUB_REACHED)), "native host must be reached");
    if let Err(reason) = observed { eprintln!("{reason}"); }
    assert_eq!(observed, Ok(1), "NATIVE_READ_RED: native host must execute exactly one admitted registered read");
}
