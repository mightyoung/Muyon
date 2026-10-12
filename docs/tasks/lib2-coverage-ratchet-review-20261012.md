# Library2 publication coverage remeasurement

Root independently reviewed fixed dc3559ca18e599f9e5a3beb8b6444b1ce5177dcb and CI38202458689, whose eight suites passed (4069P/207S/0F) but whose coverage step correctly rejected denominator drift. This failure remains recorded as failure.

GitHub artifact11726696434 metadata and ZIP digest were independently verified: 15f5780056519ffd005665a28543eb3a7993ff775a9b7aff7a6e87b5156a9c32. All437 loaded source hashes and the gated DA identities/hit counts were reconstructed. Only publication.dart changed executable denominator, 123 to126 lines, with its hit floor raised121 to124. API total DA2514 to2517; scope floor2387 to2390, below observed2391 and above every prior floor. Source inventory, measurement contract, all other API denominators and models/transfer gates are unchanged.

The baseline records only this controlled denominator and floor increase. No comparison algorithm, scope, exclusion or previous hit floor is relaxed. Final source and combination CI are still required. The model-disclosure planning denominator is a separate independently reviewed change, not measured by this artifact. Logs/proof remain outside repository in /workspace/reports/lib2-coverage-root-independent.
