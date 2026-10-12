# Model disclosure API coverage remeasurement

Independent root review of immutable source 1a963adbc8692a2cb2cbdc6328f915b1a844561f and failed CI 38201175574. Eight suites and analyze passed; coverage gate correctly rejected a changed executable denominator. The original failure remains recorded, not relabeled as success.

GitHub coverage artifact 11725188419 was independently downloaded and its SHA-256 verified: 7bd65d9e31118390fb9bf279e4930be1df2e454666e0bf5d63c52b22baac9c2b. All 438 loaded source hashes, DA identities and gate hit counts were independently reconstructed. Only planning.dart changed the API denominator: 96 to 109 DA lines, 70 to 106 hit lines. API total changes from 2514/2387 to 2527/2423. No existing per-file hit floor decreases. Models and transfer gates remain exactly equal; measurement script/hash, platform, suite set, scopes and exclusions remain equal.

The baseline is replaced by that exact measured artifact after independent review. This raises hit floors and records the controlled serialization change; it does not change the gate algorithm or waive future drift checks. This source snapshot is not a measurement of later library publication changes. Final source and combined CI must still pass against the appropriate independently reviewed denominator.

Raw logs and proof JSON remain outside the repository under /workspace/reports/model-disclosure-1a-coverage-independent.
