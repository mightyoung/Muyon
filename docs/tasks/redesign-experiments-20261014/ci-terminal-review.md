# Second-batch immutable candidate CI — independent terminal verification

**Existing CI succeeded for exact candidate `6a6664b1094c94c8db45f4ed274a170570c0cbb7`.** Run [38498073163](https://github.com/mightyoung/Muyon/actions/runs/38498073163), job [115638313638](https://github.com/mightyoung/Muyon/actions/runs/38498073163/job/115638313638), terminal completed/success. Job started 2026-10-14 **01:52:52 UTC**, completed **02:10:19 UTC**; fresh public run metadata updated_at **02:10:20 UTC**. Observer only followed this pre-existing run, without dispatch or retry.

Fresh public metadata and authorized GitHub MCP job metadata agree on run/job terminal status and exact full head SHA. New full decoded MCP job log (147618 characters) independently verified checkout `git log -1 --format=%H` producing the full SHA, eight package analyzes and eight test suites, verification-gate success, Doctor **23 scenarios**, `CI SUMMARY: OK (analyze 8/8, test 8/8 suites)`, and `COVERAGE SUMMARY: OK`. Four offline Laya script suites ran **8/4/8/9 tests (29 total)** with four OK results. Coverage summary, coverage artifact and log-retention steps succeeded.

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

All counts read from this exact new full log; no previous product or candidate run was substituted. Independently decoded this run’s gzip coverage snapshot: actions_run_id is exactly **38498073163**; all eight suite_outcomes have exit_code 0 and each pass/skip/fail summary count matches the full job log. Loaded-executable coverage and platform/model skip limitations remain.

Full decoded log SHA256: **b4f6668827c1b399970580d0ca7f9753d1e65788405467536a61abbae83e1720**. Supporting external evidence: proof.json, run-terminal-metadata.json, run-latest-public.json, run-discovery.json, coverage-snapshot.json, full-job-decoded.log. Raw logs were not committed to Git.

## Evidence scope

This is **candidate legacy regression evidence only**. Immutable `.github/workflows/ci.yml` and `scripts/ci.sh` at 6a6664b were inspected: they do not invoke the new Python experiment directories. Therefore this CI does not rerun or upgrade the separate **57 new Python experimental tests**, their six inverse mutations, classification/recovery matrices or M03 decisions. Those independent experiment results remain separate evidence. M03 stays blocked_contract; this CI proves no new native bridge, actual Android load, production signed authorization/receipt proof, complete classifier/recovery scenario or new product DTO.

No CI blocker remains for this exact candidate. Observer did not install, create credentials, change branches/product/CI, run old OC special tasks or new local experimental tests, dispatch/retry/cancel workflows, push or merge develop/main. Root owns final report publication and delivery; this terminal CI proof is not an integration authorization or a postmerge result.
