# Batch 3 tool recovery

All task tools are isolated under `/workspace/leaderb-b3-tools`; use `source /workspace/leaderb-b3-tools/env.sh` in the retained environment. No system or credential configuration was changed. Fresh environments must reinstall tools and rerun evidence they cannot recover.

Pinned components: Rust 1.99.0 minimal with `aarch64-linux-android` and `x86_64-linux-android`; Temurin JDK 17.0.20.1+1; SDK command-line tools archive `commandlinetools-linux-15859902_latest.zip` (installed revision 22.0); NDK 28.2.13676358/r28c; Platform 36 revision 2; Build Tools 35.0.0; Platform Tools 37.0.1. See TOOLCHAIN-VERSIONS.json for actual source.properties and hashes. Gradle and Kotlin/JNA use the repository's pinned, checksum-verified gate downloads.

The user explicitly approved accepting the Google Android SDK license for required official SDK/NDK compilation in the Muyon cloud, with no paid service or publication. The sole sdkmanager prompt accepted in this batch was `android-sdk-license`, SDK Agreement text dated 2019-01-16, resulting hash `24333f8a63b6825ea9c5514f83c2829b004d1fee`. No `sdkmanager --licenses` blanket acceptance was used. Preserve that narrow authorization; report materially different agreements before accepting.

Download command-line tools only from Google's repository and verify archive SHA256 `4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583`. Extract into `<sdk>/cmdline-tools/latest` with executable bin files. Run sdkmanager with the exact selected packages listed above. `platform-tools` was resolved to the recorded version in this batch; a later fresh install must record any version drift.

The managed environment has a pre-existing unauthenticated HTTP proxy. Java tools required explicit HTTP/HTTPS proxy host/port and the pre-existing `/etc/ssl/certs/java/cacerts` trust store. This was set per process, never by disabling TLS or adding trust certificates. The first SDK manifest attempts also failed because the default `/home/agent/.android/cache` was not writable. Set `ANDROID_USER_HOME` to a dedicated writable task directory with `cache/`; retain the original setup failures separately. Do not request privilege changes to fix this.

The verified command-line-tools bundle includes `bin/android`, which bootstraps Android CLI on first use. `android --version` actually downloaded/unpacked CLI 1.0.16625370 and displayed the same SDK terms URL and a usage-metrics notice; no additional agreement prompt appeared. Later invocation used `--no-metrics`; no `android init`, device deployment or emulator installation was run. The installed `android-cli` skill was read and used for the read-only SDK info command.

Official Android skills are a separate user-authorized installation; follow ANDROID-SKILLS-INSTALL.md to recover all 30 from fixed source SHA. Only load skills relevant to the current task. Installation did not authorize AGP/R8/product migrations or additional tools suggested by unrelated skills.
