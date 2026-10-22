# PR101 direct gate repair — review before first changed-source CI

Base214b4031deb38ca7dfd35ee86396089eb48157d5 preserved. New independent branch
lab/pr101-coverage-contract-fix-20261022. No retirement prerequisite mixed in.
Parent's ordinary-log DA decode (not denied artifact) pins source merge3c947f,
whose tree equals214: coverage.dart misses17/27/62; ontology.dart misses60/63/125/126.
Ontology baseline31/31 means those4 are exact loss; coverage10/11->8/11 cannot
identify which2 historical hits were lost, so legitimate tests cover all3 zeros.

Only new synchronous public-metadata tests (runtime JSON values and constructor
tearoff), bounded two-file DA diagnostics+unit test, and one exact lab branch CI
trigger. Every production lib, baseline, checker comparison, suite, and existing
CI gate remains unchanged. No empty tests or synthetic hit injection. Four tests
assert fields/defaults/immutable empty lists/page semantics/FlowStep XOR.

Diagnostic test was run RED before change, now Python coverage checker suite15
PASS. Existing Flutter is absent locally; no new Flutter installation authorized.
Dart analyze/compile/execution and coverage restoration must be established by
original CI at this changed fixed head, not static review or arithmetic. If the
seven zero records all become hit and nothing regresses,2395+7=2402>=2401; actual
result may differ and is authoritative. No old run rerun, artifact retry, CI
threshold alteration, PR101 source update or merge. One first CI on the new
reviewed branch is authorized, then monitor terminal and preserve failures.
