# Document core contracts — source delivered / HOLD

Branch: `task/document-core-contracts-20261022`.
Fixed base: `3ecb544ad0a47ccc38fe830777f35588b92e8afc`.

## Delivered scope

Pure Rust metadata and validation in `crates/muyon-core/src/documents/`:
immutable `DocumentRef`, existing `Scope`/`Revision`/`AuthorityBinding`/
`FileSource`/`ReadLease` reuse, explicit format × operation capability matrix,
host-resolved read preflight, exact scope/revision/grant checks and fresh
revocation consultation. No reusable authorization token or bytes are returned.

PDF/DOCX/PPTX/XLSX anchors bind the whole immutable identity. PDF preserves
explicit zero-based page, coordinate system, rotation, crop and unknown fields;
visible user-space selections must fit known crop. Finite positive rectangle,
normalized bounds, package part and spreadsheet bounds are structurally checked.
No page count, paragraph/shape/cell existence or target resolution is claimed.

DOC-02 safety reporting and DOC-06 revision precondition are small interface
contracts only. There is no production document host, cache access, parser,
SDK, file read/write, edit engine, transaction, UI or agent integration.
All matrix entries default to Unknown. No real format capability is enabled.

## Commits

- `85daa64449c494eb005589ca71b164a48c470951` — interface and full research
  archive; successfully pushed before implementation.
- `d038bab674b9f871fedc8de77e5f0c4b9590b571` — offline contracts and test
  source plus raw environment/test attempts.
- `3e168cfc1676772c360dfd8ac33a9551a60a592b` — independent review corrections:
  visible PDF crop bounds, isolated invalid lease generation, separate unknown
  geometry fields, normalized bounds/rotation/crop test coverage.

## Validation and evidence

From `/workspace/Muyon`:

| Command | Actual result |
|---|---|
| `cargo test --offline --manifest-path crates/Cargo.toml -p muyon-core --test documents` | NOT_RUN, shell exit 127, cargo not found |
| `cargo test --offline --manifest-path crates/Cargo.toml` | NOT_RUN, shell exit 127, cargo not found |
| `cargo fmt --manifest-path crates/Cargo.toml --all -- --check` | NOT_RUN, shell exit 127, cargo not found |
| `git diff --check` | PASS, exit 0 |

Raw logs: [test-first](evidence/test-first.log),
[initial verification](evidence/verification.log),
[review test-first](evidence/review-test-first.log),
[final verification](evidence/final-verification.log),
[environment](evidence/environment.log),
[remote/static checks](evidence/remote-and-static.log).

Tests were written before implementation and a command attempted before each
new behavior. The missing toolchain prevented a verified red/green cycle. Test
source is not passing test evidence; compilation and formatting remain unknown.
The environment search found no cargo/rustc under the installed executable
locations; no installation, credential setup or permission changes were attempted.

Independent static review of `d038bab6` found no confirmed compile defect or
authorization bypass; it raised two P2 items (crop semantics and a conflated
lease test) and geometry coverage gaps. These are corrected in `3e168cfc`.
The review does not substitute for Rust compilation or behavioral execution.
The independent follow-up on `3e168cfc` statically closed both P2 items and
coverage gaps, found no new static issue and retained acceptance HOLD.
See [independent review](INDEPENDENT-REVIEW.md). There are 18 test functions;
this is the source count, not a count of executed or passed tests.

## Remote and source custody

Initial `ls-remote` verified candidate
`codex/muyon-android-refactor=f4781e16ddf4e542b983fbd77f266a0071148255`
and UI branch `3ecb544ad0a47ccc38fe830777f35588b92e8afc` exactly.
The original `work` checkout was clean. No tracked or filesystem `AGENTS.md`
was found; UI `HANDOFF.md` and `NEXT-BATCH.md` were read before implementation.

During work the UI remote advanced to
`b6fcc030410d1718d00fbad15627423d4f809e2f`. Fetched and examined changed paths:
only UI, brand resources and associated docs; no overlap with this batch's
owned paths. The branch remains on the authorized fixed base and does not merge
the advancing UI branch.

Full Library research was read with `has_more=false`, archived byte counts
24,602 and 23,132 matching Library metadata. SHA-256:

- Office v2.0: `ac573b5bdb2795a34dcb122193d2dbc679ec1ccd8c5acc9c7c9b6728606646a6`.
- Static evidence v1.0: `50207312dd01eaec7995ad60b794e8b615b7a955b680e361d621ee46dac87101`.

No proprietary implementation copied, SDK/dependency added, file uploaded to an
engine, model/search request issued, historical unknown operation retried, or
¥0.002620 reservation altered. Main/develop were not modified; no merge, force
push, branch deletion, deployment, paid action or CI dispatch. Leader B remains
the sole develop merger.

## Remaining blockers

HOLD for acceptance: Rust toolchain absent; targeted/full offline tests and
rustfmt have no execution result. Resume those exact commands in an authorized
environment with the existing dependencies available; retain any resulting failure.

Actual host integration must atomically check current actor/project/group
membership, lease, grant and revision at byte delivery, including derived caches;
preflight alone is insufficient. DOC-02 source sniffing and malicious-input
screening, engine licensing/fidelity evaluation, DOC-06/08 durable transactions,
and real four-format reader/edit experiments remain separate unimplemented work.
This branch is reviewable source, not a complete Office editor or merge approval.
