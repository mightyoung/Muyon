# Second-batch postmerge develop CI — independent terminal verification

**Postmerge CI succeeded for exact develop SHA `325e798d37044cbc0617f5bddbd14ccb9adec390`.** This is new run [38500307094](https://github.com/mightyoung/Muyon/actions/runs/38500307094), job [115645421285](https://github.com/mightyoung/Muyon/actions/runs/38500307094/job/115645421285), terminal completed/success at **2026-10-14 02:37:32 UTC**; job started **02:18:07 UTC**. Candidate run 38498073163 remains separate evidence and was not substituted.

**Existing CI does not run the 57 new Python experiment tests.** Those tests and their inverse mutations/matrices were separate explicit commands, not added CI suites. This result is exact postmerge legacy regression evidence only; it does not upgrade new experiment acceptance or unblock M03, which remains **blocked_contract**. Immutable workflow and ci.sh at this SHA were read to confirm that experiment directories are not invoked.

Fresh public run metadata with Cache-Control:no-cache agrees with authorized GitHub MCP job metadata: exact full head SHA and completed/success. Full MCP-decoded job log (146888 characters) independently confirms checkout `git log -1 --format=%H` emitting the full new SHA; analyze **8/8**, test **8/8**, verification-gate success, Doctor **23 scenarios**, `CI SUMMARY: OK` and `COVERAGE SUMMARY: OK`. Four offline Laya scripts ran **8/4/8/9 tests (29 total)**, with four OK results. Coverage summary/artifact and log-retention steps succeeded.

| Suite | Pass | Skip | Fail |
| --- | ---: | ---: | ---: |
| module_api | 276 | 0 | 0 |
| muyon_ui | 392 | 152 | 0 |
| prototype | 39 | 1 | 0 |
| research | 365 | 0 | 0 |
| supplier_core | 498 | 4 | 0 |
| host | 2312 | 3 | 0 |
| ui_preview | 15 | 0 | 0 |
| inquiry | 302 | 47 | 0 |
| Total | **4199** | **207** | **0** |

Counts were read from this new full log, not predicted from earlier runs. The new gzip coverage snapshot was independently decoded: actions_run_id exactly **38500307094**, all eight suite_outcomes exit_code 0, and each P/S/F summary count matches the new job log. Loaded-executable coverage and platform/model skip limitations remain.

Read-only git metadata independently confirms merge parents **1dc7678684c573f7f7e26ff8c6aa2a31f4d7c22d + 6a6664b1094c94c8db45f4ed274a170570c0cbb7** and tree **37edd3f71eb6ddf3a2bc567c891eb189f9d7faf1**, matching the tested candidate tree. This observer did not perform the integration.

Full decoded log SHA256: **2d581f0e30c28b34eec1f82de6a91869b5f987c705a401874465d00499696e4a**. Supporting evidence outside Git: proof.json, run-terminal-metadata.json, run-latest-public.json, run-discovery.json, coverage-snapshot.json and full-job-decoded.log. Candidate and postmerge proof files remain distinct; raw logs were not committed.

No postmerge CI blocker remains for this exact SHA. No workflow dispatch/retry/cancel, installation, new credentials, product/branch/CI change, old special task, push/merge/revert, real model or Android operation performed by this observer. Root owns final pure-result publication. Product M03 writers remain gated on missing frozen schema, actual classification/authorization/recovery mechanisms and platform/transport evidence; CI does not establish those capabilities.
