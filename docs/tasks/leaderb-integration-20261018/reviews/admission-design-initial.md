# Independent design review — initial REVISE

Reviewer: fresh `admission_design_review`, read-only before any implementation, base `fc8ffd7e061736fdf9f4897d7c1c7914d429400a`.

The optional trusted Kotlin→UniFFI→Rust admission seam is feasible, but initial design required three corrections:

1. Rust trait defaults preserve Rust implementations; generated foreign Kotlin callback methods remain required. Handwritten ServiceHostBindings must override every new method, matching Rust/Kotlin regenerated and compiled together. No general binary/source compatibility claim.
2. Reserve retains exact full CallBudget. Existing commit signature has no budget argument, so owner retrieves and validates the stored budget instead of reconstructing it from remaining counters. Conservative total input/output token/spend obligations remain.
3. Reserve must respect immediate full-binding ensure_current: changing exposed counters/revision causes rejection. Owner owns abandoned hold release/expiry; no automatic resend.

Existence sentinel permits metadata admission only, not actual credential use/rotation identity. Atomic exact-current authority/existence and single-use durable consumption remain trusted owner obligations. Genuine generation/cmp and Kotlin/API26 compile are required evidence. No tests, network, source changes or remote mutations performed by reviewer. Initial REVISE is preserved; later correction confirmation is separate.
