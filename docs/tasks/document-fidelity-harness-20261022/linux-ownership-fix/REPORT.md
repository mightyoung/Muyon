# Linux broker confirmed-gap repair report

Source commits, each pushed on task/document-fidelity-harness-20261022:

- e46f4eab00e49a88edfee881f6d0005330846c4f: before-IPC/Popen pidfd/sealed-memfd/FD-exec capability preflight; actual artifact FD readonly mount AND readonly underlying superblock with device/mount binding; post-exec root bwrap exe/maps observation.
- 46b8dc153003f13f8880e193d9ce6b681dce21d4: mapped device+inode identity; registration before staging mkdir/open effects, partial-FD tracking, retained unknown/quarantine on cleanup uncertainty.
- 5aed4e4fca940df96bf749053fd96b22c587761c: preconfigured leaf-only resource-domain observation, reject existing children, recursive populated evidence before reap/snapshot/cleanup, and guard before recursive kill.

Only adapter/runner source and independent task documentation changed. Original /workspace/Muyon remains clean at cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003. main/develop/UI/Rust/Android were not modified or merged. The environment connection was confirmed by successful local reads, tests, commit, push and exact remote ref readback; no operation with uncertain external outcome was blindly retried.

## Validation actually run

All commands from /workspace/document-fidelity:

```
python -m unittest discover -s tools/document_fidelity/adapters/runner/linux/tests -v
python -m unittest discover -s tools/document_fidelity/adapters/runner/tests -v
python -m unittest discover -s tools/document_fidelity/tests -v
git diff --check -- '*.py' '*.md'
```

Final author results: Linux41, runner28, legacy60 PASS, scoped whitespace check exit0. Exact raw logs: evidence/linux-final-green.log, runner-final-green.log, legacy-final-green.log. Safe local file/socketpair tests and explicit fake OS syscalls only. No real native qualification/Popen, namespace/supervisor/worker/engine, cgroup kill/configuration or seccomp install was run. RED evidence for each repaired path is retained; see CHECKPOINT.md for the original domain setup errors and the corrected old-source run (nine assertion failures, zero errors). Original fixture bytes are unchanged, with hashes in SOURCE-ENVIRONMENT.json. Existing repository-wide verify is still blocked by missing flutter; its previously captured log is ../evidence/repository-verify.log. No installation or retry was performed for that unchanged blocker.

## Independent review

Fixed e46 review found the additional maps device mismatch, now repaired in 46b8. Its original source probe and independent suite logs are retained under evidence/independent-e46/. Final fixed 5aed4e4fca940df96bf749053fd96b22c587761c independent review completed: Linux41/runner28/legacy60 PASS; no new confirmed Important finding within the three scoped repairs. Raw independent logs are under evidence/independent-final/. The reviewer confirmed device+inode FD matching, ownership registration before mkdir and incremental FD tracking/uncertain-close retention, and leaf/recursive-domain guards. procs/events are not an atomic observation: disagreement conservatively HOLDs; real transient behavior is not qualified. The conclusion assumes an exclusive preconfigured leaf domain and trusted host control plane that does not concurrently reconfigure limits or migrate processes. It is not overall backend or production approval.

## Remaining execution blockers

Production remains HOLD. This branch has concrete source for backend/session/bootstrap/FD IPC and the scoped adapters, but no actual qualified native runtime. It still needs a trusted dedicated broker and predelegated bounded tmpfs/leaf cgroup; reviewed read-only runtime AND host loader/executable/review artifacts bound to actual opened FDs; fixed version/provenance/license/isolation manifests; live host scope/auth/CAS bridge; and actual compliant-environment evidence for pidfd, process inheritance, namespace/mount/NNP/seccomp/network observation, cancellation/tree reap, bounded logs, snapshots and engine roundtrip.

The existing bwrap UID-map Read-only-file-system refusal is unchanged. No retry, alternate isolation, permission or system/security change was attempted. Actual engine/library imports, document edits/reopen/render/recalc remain NOT_RUN. Formula write is not recalculation; entry evidence is not edit/render/commit success. PDF remains conservative static preflight and future annotation/sidecar boundary, no PDF editing engine. Narrow XLSX cell/DOCX run/PPTX shape subsets are not comprehensive Office editing. Unknown part/node changes still fail or are unsupported. No commercial SDK, paid action, real model/search request or real user fixture was used. Old unknown requests/reservation were not touched.
