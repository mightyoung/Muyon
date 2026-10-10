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
