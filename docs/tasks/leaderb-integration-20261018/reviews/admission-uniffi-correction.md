# Independent UniFFI compiler correction

During tests-first compilation, UniFFI0.32.2 rejected all exported trait default implementations. Fresh design reviewer inspected installed uniffi_macros-0.32.2/src/export/item.rs:204 and confirmed this compiler contract. The reviewer explicitly corrected their earlier Rust-default compatibility assumption.

Approved narrow adjustment: exported Rust ServiceHostOwnerCallback methods are required, existing owned Rust fixture implementations explicitly false/None, Kotlin ServiceHostOwnerSource keeps default false/null, handwritten ServiceHostBindings implements every required generated callback. Matched artifacts require regeneration/recompile; no general direct-interface source/binary compatibility promise. DESIGN.md:16 updated. No new file range or runtime capability. Worker retained compiler failure separately from behavioral RED. Final design approval permits only the bounded implementation; build/runtime and immutable implementation review remain separate.

Reviewer performed no edits/tests/network calls. Root did not waive compile errors or label them behavioral test failures.
