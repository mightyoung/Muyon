> Historical pre-restoration checkpoint. Superseded by REPORT.md after explicit toolchain authorization and real execution.

# Toolchain discovery follow-up — no installation

Worktree and draft remain unchanged: /workspace/office-rust-boundary-fix; task/office-rust-boundary-fix-20261023; HEAD796cdfe7cb3d79d630056239724af78128094fee. No new commits/pushes or production patches. This follow-up is read-only tool discovery, plus task evidence writes.

## Existing normal-access installations

Process is uid1000 agent; HOME=/home/agent. No CARGO_HOME/RUSTUP_HOME/RUSTUP_TOOLCHAIN/GRADLE_HOME/GRADLE_USER_HOME/ANDROID_HOME/ANDROID_SDK_ROOT/MUYON_UI_GRADLE override is present. Searched command PATH, /home/agent/.local, normal tool caches, /opt/codex/runtimes, /usr/local, /usr/bin, /usr/lib, /usr/share and the task-owned shared downloads. No cargo/rustc/rustup/gradle/sdkmanager/javac/android.jar was found. Hidden Rust/Gradle/SDK standard locations and /home/agent/.sdkman/candidates were checked specifically. Restricted session directories and credential files were not read; inaccessible /root and protected daemon/session stores were not searched or bypassed.

Prior repository logs document /tmp/muyon-combination-cargo/bin and /tmp/evidence-rust/toolchain. These exact paths, /tmp/muyon-combination-rustup and /tmp/muyon-cargo-target are absent in the current selected environment. /workspace/tools, /workspace/toolchains and common Android/Gradle installations are also absent. /home/agent/.cache/codex-runtimes links to the ordinary /opt runtime already searched; it provides no Rust/Gradle installation. Therefore no reusable trusted installation was found in the normal-access scope. This is more than a PATH-only check; it does not assert facts about inaccessible stores.

Available: curl, tar, xz, sha256sum, cc, gcc, make, pkg-config; Java runtime21.0.12.1 (/usr/lib/jvm/java-21-openjdk-amd64/bin/java -version exit0). No javac/JDK17 found. Existing project product gradlew is a shim that requires an existing Gradle and does not download one. The old Flutter android wrapper refers to9.3.1 but is not the current Rust/product build route and has not been used.

## Required fixed tools and authoritative repository references

| Purpose | Fixed version/source from this base | Discovery / authorization status |
| --- | --- | --- |
| Host Rust regression, workspace, Clippy, bindgen | Rust1.93.1 minimal + cargo/std + Clippy; product CI .github/workflows/muyon-product.yml43-44; official static.rust-lang.org | No existing install found. Fresh installation not expressly authorized by this discovery-only follow-up; not attempted. |
| Bindgen | UniFFI0.32.2, crates/muyon-android-ffi/Cargo.toml19, locked Cargo dependencies | Generate with same-source host library after Rust is available; no handwritten bindings. |
| Product Gradle | Gradle8.13 binary; product CI93-96; SHA25620f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78 | No distribution/cache found. No download/install performed. |
| Product Java compiler | Temurin JDK17, product CI73-75 (major fixed; patch not fixed there) | Only JRE21 found. A full approved JDK remains needed for this route. |
| Android SDK/native | platform android-36; build-tools35.0.0; NDK28.2.13676358; CMake3.22.1; product CI92 | No normal-access SDK found. SDK command-line tool version is not pinned by this file; SDK/EULA acceptance not authorized here and not attempted. |
| Android Rust ABIs | aarch64-linux-android and x86_64-linux-android std for Rust1.93.1, product CI89 | Not found; no target addition attempted. |

## Ordinary network availability, not an installation result

One public HEAD request each, no credentials, installation or payload download:

- https://static.rust-lang.org/dist/channel-rust-1.93.1.toml — curl exit0, finalHTTP200.
- https://services.gradle.org/distributions/gradle-8.13-bin.zip — curl exit0, official redirect chain finalHTTP200. Public signed redirect query removed from saved headers; status chain retained.
- https://dl.google.com/android/repository/repository2-1.xml — curl exit0, finalHTTP200 (repository availability only, no SDK license acceptance).

Saved under evidence/*-official-availability.log. Public official endpoints are reachable in the ordinary environment. This does not establish downloaded archive hashes, install compatibility, license acceptance or any Rust/Android test result. A future authorized task-local install can pin and verify official artifacts without sudo/global changes, but this follow-up has not installed anything. No quota/model failure, auto-review denial or unknown mutation occurred. Fresh download/install authority or a parent-supplied existing toolchain path remains needed before actual RED can run. Original NOT_RUN127/2 logs and17 passing existing Android checker tests remain accurate; do not rerun them unchanged or call missing-tool execution a regression failure.
