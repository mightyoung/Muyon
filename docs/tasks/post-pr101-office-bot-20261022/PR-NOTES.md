# Rust Office preview and native Bot draft prepare wiring

Adds the reviewed on-device Rust OOXML engine and UniFFI preview/candidate API, including phonetic-text suppression and bounded edit output. Connects the existing Service prepare method to the real ten-field generated record, preserving the captured attempt/archive and verified=false. Based on merged PR101; its contract/coverage repair is retained.

No publication, live model/search call, full Office visual fidelity/recalculation, or native Service/device acceptance is enabled. Android compilation/lint of this combined candidate remains NOT_RUN in this selected environment; the new PR's product CI must validate it. Predecessor Android results are recorded separately.

Validation evidence, exact source pins, failures and independent reviews are to be attached from docs/tasks/post-pr101-office-bot-20261022. Full-tree fmt has inherited failures; seven new Office/FFI files have pure rustfmt and an independently verified diff. No baseline/threshold/workflow changes.
