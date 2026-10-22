# Existing task-local toolchain after authorized restore

Only Rust was needed/restored for this prerequisite. Official rustup-init1.28.2
archive was downloaded from static.rust-lang.org and checked against its official
sha256; toolchain1.93.1 minimal+clippy+rustfmt. No PATH/profile/global configuration,
new credential, elevated installation, Android license acceptance or paid runner.

For this same execution environment only:

```sh
export RUSTUP_HOME=/tmp/muyon-retirement-rustup
export CARGO_HOME=/tmp/muyon-retirement-cargo
export PATH=/tmp/muyon-retirement-cargo/bin:$PATH
export CARGO_TARGET_DIR=/tmp/muyon-retirement-target
export RUSTFLAGS='-L native=/tmp/muyon-retirement-native'
```

Cargo absolute path `/tmp/muyon-retirement-cargo/bin/cargo`; use `+1.93.1`.
Native SQLite linker alias in task-local directory points to preexisting
`/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`, no system library installation/change.
Compiler identification and command timestamps are in verification JSON logs.
Gradle/Android/Flutter remain absent/NOT_RUN here; no assumption of cross-machine
cache persistence or artifact availability. Never run legacy I04 suites to test
this toolchain; only named supplier_store and product workspace graphs authorized.
