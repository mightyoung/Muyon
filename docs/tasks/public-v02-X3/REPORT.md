# X3 preliminary read-only assessment — HOLD

2026-10-23 UTC. Parent authorized read-only fixed-version/license/interface
research, not SDK installation or new dependencies. Deliverable:
[public-services-mcp-sdk-gate.md](../../implementation/public-services-mcp-sdk-gate.md).

Read official GitHub tag objects, immutable source manifests/licenses, recursive
trees, Rust transport and Kotlin client/build declarations. Rust plan tag
rmcp-v3.7.0 resolves through annotated tag
`cdf95e06d7cc2a13f9ff97e3e5d6cf1226630ae9` to source
`5d6a11f2ae022f513aec0f6e0f10f89a57891a7f`; Kotlin0.15.0 resolves to
`76b8e7d63aac39fe41e03684e3b91a6c3724a8da`. Direct immutable source citations
and relevant blob IDs are in the gate document. No default-branch guess used.

Recommendation is to keep installation blocked. A future smallest-feature
Rust-client/in-memory evaluation can be considered after license/artifact/closure,
Android and trusted host gates, while Kotlin remains an alternative needing its
own engine/metadata compatibility evaluation. Both introduce dependencies outside
the current lock; no dependency was installed, fetched with Cargo, built or added.

Fixed-source license text is now readable; published package licenses/NOTICE and
transitive closure are NOT_REVIEWED. Rust declared MSRV is only a source fact,
not a successful compile. Kotlin JVM target and client API declarations do not
prove Android compatibility. Proposed adapter boundaries are documentation only;
no new public command, host authority, secretRef issuer or execution ledger.

X3 gate RED/HOLD is a documentary prerequisite assessment, **not a behavioral
test failure**. No X3 RED/GREEN, SDK unit/integration tests, Android, OAuth or remote
effects ran. Existing X1/X2 tests do not validate an absent SDK adapter.

Independent read-only reviewer `/root/review_connector_lifecycle` checked fixed
document source `e68479fa512f37df3c7a31da87c67c3acb842a09`, official immutable
citations and local platform declarations. No P0-P2 findings. One P3 citation
issue was corrected: the Rust package LICENSE entry is a symlink, while the
actual license text is in root LICENSE blob
`4a93985763241755401a10678395303de4e720ba`. The root file was independently
retrieved before applying this correction. No SDK tests or installs occurred.

No final SDK selection, license approval, gate GREEN or product acceptance is claimed. B remains sole
merger; Contracts alone registers shared modules. No denied operation or uncertain
write occurred during these read-only lookups.
