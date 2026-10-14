# RD-P03 fixed-head follow-up independent review

Fixed head `e80d5077d4d41366336d59fd1b143ed5af04f55a`; predecessor reviewed
`abf67478f341bfc726060f59ae894af0e8f8fa93`. Independent git archive at
`/tmp/rd-p03-independent-fix-review-20261014`; all 11 source/evidence/task files
match exact fixed git blobs after tests (blob-proof.json).

## Conclusion

**Bounded C0 for experimental mock-assets intake.** Prior P03-R1 unknown reload
bypass and P03-R2 malformed receipt acceptance are closed in the tested fixed
head. Integrator still owns combined regression/candidate CI before develop
integration. This is not production authority, native bridge, Electron runtime,
Android or full M03 acceptance. No new important failure found in this follow-up.

## Actual fresh executions

Nine executable verification commands:
- `node --test tests/*.test.mjs`: 27 passed / 0 failed / 0 skipped, exit 0,
  node-tests.log.
- Three `node --check` commands for app.mjs, electron-main.mjs, preload.cjs:
  exit 0 each.
- `node --test <report>/probes.mjs`: 7 passed / 0 failed / 0 skipped, exit 0,
  probes.log. Independent probe source stored beside report.
- Three `node --test tests/model.test.mjs` executions in separate mutant folders:
  each exit 1 at assertions, logs named for mutants below.
- `npm test` on untouched archive after mutants: full 27 passed / 0 failed /
  0 skipped, exit 0, restored-npm-test.log.

## Regression and binding confirmation

Old unknown path: lost response → load → ordinary edit → preview/save. Original
intent/raw remain owned, phase remains unknown, dispatches stays 1 (zero new
dispatch). Independent instrumentation then verifies lookup receives the original
intent and recovers its receipt without dispatch; ready only follows that account.
A read/snapshot alone cannot mint another intent or clear unresolved ownership.

Independent malformed-response probes use complete otherwise-valid receipts from
actual MemoryRustCorePort commit, modifying only the field under test. Empty id,
negative result revision, wrong expected revision, unchanged result and wrong plan
all remain unknown, enter no ledger and preserve the unresolved command. This
avoids the weaker old examples where missing other binding fields could reject
an empty-id receipt for the wrong reason.

Command is registered and immutable; account checks original intent, supplier,
planId, expectedRevision, nonblank receipt reference, result revision exactly
expected+1 and committed normalized name. Preview binds raw, original identity and
expected revision, and only accepts a positive safe JS expected integer below
MAX_SAFE_INTEGER. These numeric conventions are declared mock-only, not M03 wire
encoding or authority over opaque product revisions.

`isolateUnresolved()` is an explicit separate API/UI action. It creates a different
user draft while retaining the original unresolved command. Ordinary load/edit
cannot do this; save is blocked while the original is unresolved. Independent
probe confirms original lookup enters only the original receipt in the ledger,
clears original ownership, preserves new raw/intent and leaves displayed receipt
null with no second dispatch. Old-epoch real mock effects are therefore accounted
without overwriting a newer draft. Native provenance is still NOT_CONNECTED.

## Independent mutation checks and byte restoration

- reload-clears-command: inject clearing unresolved on snapshot read; exit 1 at
  unknown reload/navigation assertions.
- blank-id-accepted: remove only nonblank account guard; exit 1 at complete
  whitespace-reference assertion.
- invalid-revision-accepted: remove only expected+1 relation; exit 1 at result
  revision rejection assertions.

Mutations are in `/tmp/rd-p03-independent-fix-mutants-20261014`, not author source.
The archive model SHA256 before/after is equal; mutation-proof.json records actual
exits and equality. All 11 archive files also match the immutable git head after
restored full suite. Author mutant summary/logs were read; independent execution
supplies the acceptance evidence, not the author's assertion alone.

## Renderer, bridge and browser limits

Source/syntax checks preserve textContent/value for untrusted supplier/receipt
text; no innerHTML, shell, DB or generic authority-bearing IPC was added. Electron
main retains nodeIntegration=false/contextIsolation=true/sandbox=true and denial
of external windows/navigation. Preload exposes only static mock metadata.
Renderer now has explicit reload/isolate/lookup buttons; save is disabled by
unresolvedIntent. This UI is synthetic and cannot grant production authority.

Read the author's fix dom-result.json and app smoke path: finite Chromium CDP
result passed and checks two distinct resolved-intent dispatches stay 2 across
unknown reload/original lookup. Existing 200% measurement is width1280,
scroll1265, rawBottom833.859375, saveTop949.859375. This read does not constitute
independent browser reexecution, full keyboard/accessibility or Electron evidence.
No Chrome/Electron/Android process was started by this reviewer.

Electron actual runtime **NOT_RUN**, Android actual load **NOT_RUN**, native port
**NOT_CONNECTED**, M03 **blocked_contract**. Durable restart, true trust/permissions,
stream-domain watermarks, read revocation and full device/release acceptance remain
required work. No author modification/commit/push/merge, installation/license,
credentials or real data action occurred; old OC reviews were not rerun.
