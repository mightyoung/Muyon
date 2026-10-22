# Accepted APK delivery

[Native Library download](https://chatgpt.com/api/library/files/libfile_cca1bb43d0cc8191b6113d9c0d9e9c70/download). Confirmed Library create succeeded; local identity/version metadata persisted successfully. `libfile_cca1bb43d0cc8191b6113d9c0d9e9c70`, filename `Muyon-frontend-service-loop-2f8f4da6-debug.apk`.

| Property | Verified value |
| --- | --- |
| Source / CI | `2f8f4da674e871708880dcc792a1c9dafb3a17f3` / successful39107347147 |
| Package | `com.mightyoung.muyon.androidlab` |
| Version | `0.0.1-lab`, versionCode1 |
| Minimum / target SDK | 26 /36 |
| Native ABIs | arm64-v8a, x86_64 |
| Bytes | 23,284,076 (22.21 MiB) |
| APK SHA256 | `67bca372b01973b46926406efcbfd4fb6aaf95c42a94643690444f58c7efce41` |
| Signing | APK v2 verified; one self-signed Android Debug certificate; no verifier errors/warnings; v1/v3 absent |
| Signer certificate SHA256 | `3d3583021b10ae085ae026ab85d4e8bec9a4cdd82712454e99d551a834005e89` |

Signature checked against the exact downloaded APK using official Google Maven apksig8.11.1. Raw verifier result, tool artifact hash, CI aapt2 badging and Library confirmation identifiers are in `final-evidence/apk-signature-verification.txt`, `source2f-apk-badging.log`, `library-apk-delivery.json`. This is a debug lab build, not a release-signed production update. No signing key was exported or configured. The Library copy is byte-identical to the CI APK.

## Installation and local data

This delivery did not install or uninstall anything. A fresh installation creates this lab package's sandbox when used. It persists original request identities/text/receipt identity in private `supplier-read-identities-v1` preferences and Service run/receipt/synthetic-source state under private `files/agent-service-root`; UI local notes/view state also belong to the lab. It reads only its fixed synthetic schema12 copy, not a production user database. Manifest has no INTERNET or external-storage permission and disables backup.

An existing installation of the same package can be updated only when Android accepts its version and signing identity. This CI-generated debug certificate has not been compared with any APK on the user's device; do not promise an in-place update. A different signer is normally rejected. Uninstalling to resolve that mismatch removes the lab package's local requests/receipts/data; no uninstall or data reset is authorized or performed by this delivery. Other package IDs have independent app sandboxes. Physical-device installation is NOT_RUN.

Capabilities remain synthetic deterministic supplier reading with ordered result batches, ORIGINAL receipt and lookup-only Service recovery, proven on CI API26 x86_64 emulator. Live model, production scope bridge and model-token streaming remain unavailable. [Next-session dependencies](NEXT-SESSION.md); [full retained verification/failure ledger](FINAL-VERIFICATION.md).
