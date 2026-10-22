# FS01 additional public-API resource boundaries

Only `crates/muyon-core/tests/resource_boundaries_additional.rs` and this record
are added. No production code, dependency, schema, device operation, Gradle,
network request or model call changed. Existing archive rejection fixtures,
small blob tests, sparse-file unit quotas and 2 MiB opaque-stream regression
already cover different claims; these tests add the previously missing exact
inclusive limits using public APIs and real input bytes where practical.

## Three tests and their evidence

1. `actual_pdf_and_document_exact_thirty_mib_and_one_extra_byte` sends real
   64 KiB chunks through `begin_upload`/`append_chunk` for each Pdf/Document
   kind. Exactly 31,457,280 bytes successfully finish and read back with exact
   SHA-256/length. Exactly 31,457,281 bytes return **TextLimit**; this is not an
   any-error assertion. Independent read-only SQLite counts show no new blob,
   pin, reference or business history from refusal. The rejected original file
   retains its entire length and actual digest, and the prior valid blob still
   reads correctly. Payloads have only a basic PDF envelope: this does not prove
   that a full PDF renderer will accept a 30 MiB document.

2. `zip_metadata_exact_expansion_and_member_count_and_one_over` constructs real
   ZIP32 local/CEN/EOCD byte sequences. Five 30 MiB expanded-size declarations
   (157,286,400 total) pass metadata limits; adding a separate one-byte member
   returns **TextLimit**, without tripping the per-member limit first. Exactly
   10,000 unique regular STORED empty members pass; 10,001 return **TextLimit**.
   The large expanded sizes are **declarations only**: their tiny DEFLATE
   payload does not contain 150 MiB of decoded bytes. The test also requires
   the decoded-content validator to reject empty actual data for the declared
   30 MiB entry. Metadata success is not inflation, CRC/content certification,
   actual 150 MiB archive transfer, or publication acceptance.

3. `seal_actual_total_exact_one_fifty_mib_then_one_byte_and_member_count_refuse_without_effects`
   sends five independent actual 30 MiB uploads through the same public upload
   APIs and seals five distinct PDF paths with `seal_research_snapshot`. Their
   total verified input payload is exactly 157,286,400 bytes. Equal content
   legitimately deduplicates to one 30 MiB object; no rows, file lengths or
   descriptors are injected. This is actual aggregate input accounting and
   sealing, without storing 150 MiB of distinct content. Adding a real one-byte
   document returns **TextLimit** and leaves upload/blob/pin/history counts
   unchanged. An over-count 10,001-entry request also returns **TextLimit**
   before resolving unissued placeholder upload IDs. The previously sealed
   manifest and actual source blob still read back with exact digest/length.

Every disk-backed test asserts zero research entries and zero blob business
references, with only the legitimate project-setup history row. Sealing is a
prepared snapshot, not business import publication. These tests intentionally
do not dispatch an import merely to test a resource refusal.

## Storage budget and cleanup

The test file has exactly three tests. A generated payload uses one reusable
64 KiB memory buffer. In each disk fixture all 30 MiB valid uploads have equal
content, so only one content-addressed object is stored. At most the original
30 MiB source and a separate 30 MiB publication copy/object coexist per fixture;
oversized rejected originals add only one byte. Two disk tests can run in
parallel, giving about 120 MiB of controlled payload files plus small SQLite/
manifest overhead, below the 200 MiB task budget. The ZIP metadata test stays
in memory (about 1 MiB per member-count archive), not a giant disk fixture.

Each fixture uses its own `muyon-resource-boundaries-<pid>-<counter>` namespace
under the standard temporary directory, and its Drop guard recursively cleans
only that namespace after database handles close, including on assertion panic.
No unrelated host files are removed. Post-run inspection found zero remaining
owned fixture directories.

## Executed checks

From `/private/tmp/muyon-android-refactor-20261020`:

```sh
cargo test --manifest-path crates/Cargo.toml --offline --locked -p muyon-core --test resource_boundaries_additional -- --nocapture
```

Result: **3 passed, 0 failed, 0 ignored**, exit 0; runtime **26.97 seconds**.
`rustfmt --check --edition 2021 crates/muyon-core/tests/resource_boundaries_additional.rs`
and `git diff --check` returned exit 0.
`cargo clippy --offline --locked -p muyon-core --test resource_boundaries_additional -- -D warnings`
returned exit 0 with no warnings.

Frozen test file SHA-256:
`7ba9ef1b27774aef5581f25bcb3e1fc547e801c2597fffd818619c254ebfe26b`.

## Explicit remaining boundaries

- Positive 10,000-entry **actual seal** would require 10,000 distinct issued
  upload identities; this narrow run does not manufacture that ledger or spend
  10,000 durable filesystem-upload cycles. The positive count boundary is proved
  for public ZIP metadata parsing; actual seal count-overflow preflight is
  proved separately. Full 10,000-attachment seal/import remains **NOT_RUN**.
- No full 150 MiB compressed archive was uploaded or inflated. Actual aggregate
  150 MiB input through five uploads is separately proved with deduplication.
- Distinct-content 150 MiB storage, full business import of these large inputs,
  API26 memory/latency behavior, power-loss recovery and I04 remain **NOT_RUN**.
- Host public-API resource proof does not replace device/product acceptance.
