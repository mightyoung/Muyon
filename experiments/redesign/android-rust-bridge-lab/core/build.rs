fn main() {
    println!("cargo:rerun-if-env-changed=MUYON_BRIDGE_BUILD_ID");
    let identity = std::env::var("MUYON_BRIDGE_BUILD_ID")
        .expect("MUYON_BRIDGE_BUILD_ID must identify the fixed build source");
    assert!(
        identity.len() == 40
            && identity
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)),
        "MUYON_BRIDGE_BUILD_ID must be 40 lowercase hexadecimal characters"
    );
    println!("cargo:rustc-env=MUYON_BRIDGE_BUILD_ID={identity}");
}
