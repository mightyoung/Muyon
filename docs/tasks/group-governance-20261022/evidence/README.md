# Evidence supplement

Source commit: `2cc5df1c900cd2977e8bdf4ca623e82f673a50b7`. This supplement changes reports/evidence only. The later explicit parent request to retain raw evidence supersedes the earlier choice to leave it in /tmp.

- `historical/green.log`: retained original final standalone stdout, **21 passed**.
- `historical/cargo-final.log`: original combined stdout/stderr, **168 passed**, zero failed/ignored, including the 21 governance tests. No new 168-test rerun is claimed. Existing dependency warnings remain verbatim.
- `historical/cargo.log`: earlier **167 passed**, using the earlier 20-test version; kept distinct.
- `historical/mutations/*.log`: six original mutation outputs on the **20-test / pre-unknown-child-fix** source. Lifetime-cap mutation reports two failures; the other five report one each. These are expected mutation detections, not failures in final source.
- `historical/mutations/baseline-*.rs.txt` plus individual patches reconstruct every exact old mutated module/test input. Their commands.json records original argv reconstructed from the recorded orchestration and exact input hashes. Compiler output was not saved. Original orchestration asserted compile success and nonzero test status but did not print numeric test status; that number is left unset.
- `historical/red.log`: original 17-test stub behavior RED, **3 passed / 14 failed**. Original stub source is unavailable. That shell ended in cat, so its successful shell status is not the test status.
- `fresh/`: NEW final-source compile, **21 passed**, fmt and diff-check, executed from **2026-10-22T03:55:31.983791+00:00** through **2026-10-22T03:55:32.274934+00:00**. Separate stdout/stderr and manifest retain exact argv, actual per-process times/exit codes, selected environment fields, compiler versions/binary hashes, source/lock hashes and SQLite target/hash. These new outputs are never represented as old outputs.

Every `.junit.xml` is **derived from its sibling raw libtest log**, not native runner output. `convert_junit.py` verifies parsed case counts against summary totals, omits unavailable durations and embeds raw-log hashes; `junit-summary.json` records counts. Reproduce with `python3 docs/tasks/group-governance-20261022/evidence/convert_junit.py` from repository root. Missing compiler output/native JUnit/environment snapshots/RED files are documented in historical manifests rather than invented. Original mtimes are filesystem metadata, not execution timestamps.

`SHA256SUMS` hashes all other evidence files, excluding itself. Run `sha256sum -c SHA256SUMS` here. Archived original outputs are byte-compared with surviving /tmp files before commit. No executable binary, downloaded toolchain, credential, real receipt or user accounting state is included.

Four Grant layers still require production mapping to **user authorization / group policy / task policy / current tool policy**, provenance checks and member-capability intersection. That adapter is not wired or certified. **Eligible is only advice and cannot unlock execution**, external actions, paid transport, automatic groups, a lease or a bypass of original unknown/receipt checks. The sole host gateway and all prior HOLDs remain required.

After staging the preserved outputs, full `git diff --cached --check` returns exit2 solely for libtest’s original final blank line in 11 raw `.log` files. The raw bytes are intentionally retained. The authored-evidence check excluding only raw `.log` paths returns exit0; exact commands/output are in `fresh/staged-whitespace-check.json`. The earlier fresh diff-check ran before these previously untracked artifacts were staged and is not claimed as an archive-wide whitespace pass.
