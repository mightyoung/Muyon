# SDD ledger — plan: docs/superpowers/plans/2026-10-23-connectors.md

Plan source 64900d4a6a46a9ef2919bcf922fb059413b1ce82. Latest develop re-fetched fd26dcdabcdac996bc2881e8141cac2b519966fc. Parent explicitly released candidate contracts 4d49a580cb518d9b0b80c9df3df1ff564194a639, not merged develop; ordinary merge preserves provenance. C1/C2/C3 source, fixtures and REPORTs read.

Pre-flight X1/C1: reuse services::types::{Digest,UnixMs,ScopeRef,ServiceError}; Revision remains contract::Revision. X2/C2: reuse unphased_host_error for unknown recovery, no HostCommandPort implementation or new Operation. Money/Quantity/phase enums untouched.

Ruling: tests compile the actual unregistered module via #[path] and alias the existing contract/types modules at test crate root — Contracts alone owns registration, and this permits behavioral TDD without editing owner files — library export remains pending until owner registers modules.

Ruling: P1 config schema is exactly the trusted built-in endpoint/optional label object with additionalProperties=false, no generic JSON schema interpreter — arbitrary descriptor schemas are unavailable — future adapters with other public fields require review.

X1 in progress; no behavioral RED/GREEN yet.
