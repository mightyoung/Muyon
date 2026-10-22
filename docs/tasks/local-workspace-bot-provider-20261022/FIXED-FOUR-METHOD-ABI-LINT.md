# Four-method fixed ABI — narrowly scoped Clippy exception

Parent authorization explicitly permits only local_draft_save's
clippy::too_many_arguments exception to preserve the already generated UniFFI ABI.
Read fixed B82169330ff6868b5979e351056d538dd496e9519 STRICT-GATE-REMAINING.md.
This branch starts from provider8b2d7783a0bfe5c5207edb7cf37a83631f1cfb0f;
it contains NO fifth method, prepare journal, new core source, behavior/test changes,
new generated Kotlin, Service/Runtime edit or next-batch dependency.

The sole production change is a reason comment and #[allow(clippy::too_many_arguments)]
on ProductCore.local_draft_save ONLY. No impl/module/crate/global allow and no other
lint is disabled. Its nine explicit parameters plus self retain types/order/name.
Existing Kotlin Service calls localDraftSave with nine positional arguments at
Host9d2c4119d0c66d1748955cee1d86e63deb7ce16f ProductService.kt:131.

A record parameter is supported by the repository's existing UniFFI examples, but
cannot transparently replace this fixed method: generated signatures/checksums and
Host calls change. Keeping a compatibility wrapper would still leave this exact
wide ABI method. Therefore a unilateral record conversion is not this gate fix.

For a future coordinated versioned API, introduce a typed request record, regenerate
bindings and update Host, then retire the compatibility method deliberately. The
queued fifth prepare method is not part of B's current435/four-method ABI and will
use a typed request record BEFORE its first accepted generation; that is a separate
owner source release and must not be accidentally imported with this patch.

FIXED-FOUR-METHOD-ABI-LINT.patch is generated against B's exact FFI source82169330.
It adds the same three lines only, so B may apply it without adopting this branch's
old core/dependency history. Do not import the queued five-method journal source
merely to close the current strict gate.

Local git diff --check passes. Current environment lacks cargo/rustc/rustfmt;
new-source Clippy/tests/generation remain NOT_RUN. Historical B435/four-method14
behavior PASS and strict-gate FAIL are unchanged evidence, not this patch's PASS.
B independently reruns complete strict Clippy plus required fixed-source checks.
No test/assertion/lint behavior was weakened beyond the expressly permitted single
ABI argument-count exception; no account/permission/credential/engine change.

Independent read-only review: no findings; removing the three new lines restores
base FFI bytes exactly. Patch context matches exact B source; no fifth/core/journal
change. Pre-existing unrelated method allowances are preserved, not added or removed.
