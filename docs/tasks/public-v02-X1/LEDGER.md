# SDD ledger — plan: docs/superpowers/plans/2026-10-23-connectors.md

Plan source 64900d4a6a46a9ef2919bcf922fb059413b1ce82. Latest develop re-fetched fd26dcdabcdac996bc2881e8141cac2b519966fc. Parent explicitly released candidate contracts 4d49a580cb518d9b0b80c9df3df1ff564194a639, not merged develop; ordinary merge preserves provenance. C1/C2/C3 source, fixtures and REPORTs read.

Pre-flight X1/C1: reuse services::types::{Digest,UnixMs,ScopeRef,ServiceError}; Revision remains contract::Revision. X2/C2: reuse unphased_host_error for unknown recovery, no HostCommandPort implementation or new Operation. Money/Quantity/phase enums untouched.

Ruling: tests compile the actual unregistered module via #[path] and alias the existing contract/types modules at test crate root — Contracts alone owns registration, and this permits behavioral TDD without editing owner files — library export remains pending until owner registers modules.

Ruling: P1 config schema is exactly the trusted built-in endpoint/optional label object with additionalProperties=false, no generic JSON schema interpreter — arbitrary descriptor schemas are unavailable — future adapters with other public fields require review.

X1 RED source c8fbca09f60832ec4ef4fbe92d07e2a74bb4833e: 0 passed/7 failed (compiled unavailable stub). GREEN 7 passed/0 failed. Core regression offline/locked exit0; exact count/report follows. Raw output stays outside git.

X2/C1 ruling: permission strings are kind-qualified tool:name, resource:name, prompt:name — same-name capabilities must not share a grant — callers using legacy bare names will be denied until explicitly adapted. This is a Connector-local key convention, not a shared C1 type.

X1 is implemented as local module source; independent review and Contracts registration still pending. No transport/credential store/production dispatch.
