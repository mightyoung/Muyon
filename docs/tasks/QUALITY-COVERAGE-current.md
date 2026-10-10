# QUALITY-COVERAGE current integration measurement

Authorized restart on 2026-10-10, based on develop
`d3deca3b3bb3ecdb45e53f5f6fb22878fcc4bec9`, isolated branch
`task/quality-coverage-current-20261010`.

The previous PR23 implementation at
`30439f7c0a22d5d1ed9646120c65d6e190ec1f85` is carried forward only for
coverage CI/checkers and its unique codec regression file. No production codec,
owner tests, lint configuration, or business behavior is changed.

The legal fact-bound control now uses schema2. An explicit library-2/schema1
rejection remains alongside both legacy collection decode rejection cases.
The DA diagnostic records source hashes and exact DA identities for every loaded
repository lib source across the eight existing suites, not only six API files.
All unloaded executable denominators remain unknown. Raw LCOV/logs remain outside
Git; only derived diagnostics are retained by the existing CI artifact.

The first measurement deliberately retains the previous machine baseline and
checker unchanged. Its expected drift failure is evidence, not a successful gate.
A baseline update requires complete fixed-SHA eight-suite measurement and review
of inventory, per-file DA sets, source identity, hit changes and unknowns. No
threshold relaxation, source exclusion, or automatic baseline acceptance is added.

Local checks: coverage checker 9 tests, DA diagnostics 5 tests, verification gate
10 tests passed; bash syntax and diff whitespace passed. Flutter/Dart are absent
in this cloud workspace, so no local Flutter success is claimed. Remote run and
measurement results are pending.

## Initial typed-product drift evidence (not the final baseline)

PR34 [CI 38043287264](https://github.com/mightyoung/Muyon/actions/runs/38043287264)
measured merge SHA `64d4931a0ebf4578d5edd9b911d90f2ab0c2443b`.
The only gate failure was `denominator drift: packages/muyon_module_api/lib/`.
Analyze 8/8 and test 8/8 passed, including API 194, UI 373 with 152 skips,
and host 1528 with 3 skips. Laya was skipped after the expected earlier failure,
so this run is not a complete green integration gate.

All eight reports were present. All 401 loaded-source SHA256 values matched the
measured Git tree. There were no missing/untracked loaded sources. Nineteen
unloaded source files still have unknown executable denominators; whole-package
percentages remain unknown.

| Gate | Previous hit / loaded DA | Current hit / loaded DA | Inventory |
|---|---:|---:|---|
| module API lib | 1298 / 1389 | 2075 / 2191 | 28 to 32, no removals |
| model services | 751 / 778 | 751 / 778 | unchanged 10 |
| transfer services | 827 / 882 | 827 / 882 | unchanged 3 |

The four added API files are collection, edit_spec, publication and recomputation.
Every changed loaded DA fingerprint belongs to a newly added or actually changed
API source; unchanged gate sources have no denominator or hit decrease. Model
and transfer source bytes, inventory, denominators and hit counts are unchanged.
Historical baseline DA identities cannot be recovered from their fingerprints;
this comparison does not claim a reconstructed historical line-by-line map.

No baseline is reset from this sample. Final measurement must include the
independently reviewed lint and AIUI recovery production combination, with its
own exact source hashes and full eight-suite evidence.

The exact-source [push CI 38043209322](https://github.com/mightyoung/Muyon/actions/runs/38043209322)
measured `debfbb8c94575991476c23f756ef4671b4be4d29`: analyze/test 8/8
passed and only the old API denominator gate failed. API was **2076 / 2191**,
one hit above the PR measurement. All source hashes and loaded DA identities
match across the two measurements; all other package/gate data match.
The sole discrepancy is `edit_spec.dart:83`, the const UiBoolEdit constructor,
which was hit only by the push run. The const UiDateEdit constructor at line156
was unhit in both. This is a reproducibility blocker before freezing a new
per-file hit baseline; it is not removed, ignored or converted into a lower floor.
The coordinator authorized the unique independent
`ui_edit_spec_runtime_coverage_test.dart`. Runtime-decoded metadata constructs
bool/date specs without const canonicalization; assertions verify strict boolean
payloads/nullability, real leap dates, inclusive bounds, invalid types/formats and
reversed ranges. No production or owner-test edit is made. Remote execution and
stable constructor DA hits remain pending; no success is inferred from source review.

The all-source diagnostic fixture additionally asserts a lib source outside the
six historical target files. It fails against the historical diagnostic and
against a mutation restricting the current diagnostic back to those six targets,
and passes against the current implementation. These temporary mutations and
raw test output are not committed.
