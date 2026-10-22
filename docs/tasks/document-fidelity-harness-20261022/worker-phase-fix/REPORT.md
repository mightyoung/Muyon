# Worker-phase / TTL / engine-accounting correction report

Base `7fb2c8ef82b30ee6572119016c8bb906733c129d`; branch `task/document-fidelity-harness-20261022`. Initial source `fa2aa13a6f7dc1189b68b11b96b28524b4500e46`; final source `ab28bb0899bd6eb17d98ace9f8b0db0d25d8e205`. A later docs/evidence seal has no source changes; final remote tip is returned after push/readback.

## Corrected behavior and separate evidence

1. Worker execution authority now closes before any stop/TERM/KILL/reap/reconcile/cleanup/quarantine callback, including the normal exit/reap path. It atomically revokes all preissued worker permits. Both mint and consume check the worker phase; consume rereads its parent. The admission/validation phase stays separate so a reaped valid candidate can still undergo normal independent verification. Initial `evidence/red.log` has21 tests/8 callback failures; targeted `window-green.log` passes all8 fresh/preissued × cancel/success/unknown/reconcile combinations. This closes the stopping-window gap, rather than only revoking when run_production returns.
2. After verify_terminal returns, Authority rereads trusted backend monotonic time and rechecks exact live admission lease before mint. Separate ttl-red.log reproduces expiry15 while callback advances10→20 under operation deadline50; ttl-green.log withholds candidate and credential instead of publishing expired success. Previously consume_credential already rejected at20: this was an inaccurate success report, not evidence of an authorization bypass.
3. Spawn alone never labels engine executed. worker_process_started is false before attempt, null while outcome is uncertain, true with a known/reconciled handle. engine_execution becomes unknown at attempted host spawn; it can become executed only after separately authenticated typed HostExecutionEvidence bound to exact attempt/engine artifacts. Missing/JSON/wrong-engine/wrong-binding proof stays HOLD without candidate/credential. Base verifier provides no execution proof. Separate execution-red/green and uncertain-spawn-red/green logs retain tests; a worker exit before engine import never establishes engine execution.

The receipt3 nullable-bool addition is an explicit proposal update: unsupported consumers must HOLD rather than coerce null to false. Schema1/2 edit requests remain unchanged; no Rust/Android consumer is wired or modified. Worker output JSON is not authenticated engine-entry evidence. Future real broker/IPC must provide the source and authenticity of that observation; it is not implemented here.

## Independent review and fixes

Initial immutable fa2 review verified3 corrections and25+60 tests, then found2 adjacent P2 contract issues: ready verifier could close worker phase reentrantly while approval/spawn continued; terminal verifier could reenter issuance before its single-use marker, minting2 synthetic validators. Neither probe establishes an untrusted-JSON bypass or genuine host credential. Original report/scripts/logs are preserved verbatim in evidence/independent-initial/.

Author TDD fixes: approve_ready rechecks phase after callback; pre-spawn uses claimed/ready/open check_worker_lease instead of admission-only check. Credential issuance reserves its only attempt before calling the verifier; recursive issuance refuses. Separate reentrant-red/green and credential-reentrant-red/green logs preserve both failures and fixes. Normal synthetic candidate validation and one-use/expiring consumption continue to pass. Final author28 runner+60 original tests pass.

Final independent recheck of exact immutable source `ab28bb0899bd6eb17d98ace9f8b0db0d25d8e205` PASS:28 runner+60 original tests,18 pure-fake contract cases/assertions, no remaining actionable finding reported. The reviewer exported a separate git-archive snapshot; this is an independent final-source recheck, not merely author replay. Exact report/raw scripts/logs are retained in evidence/independent-final/. These synthetic tests do not qualify real engine/host/sandbox execution.

## Commands and results

| Command | Result |
|---|---|
| `python3 -m unittest discover -s tools/document_fidelity/adapters/runner/tests -v` | Author28/28 PASS, exit0; evidence/runner-final.log |
| `python3 -m unittest discover -s tools/document_fidelity/tests -v` | Author60/60 PASS, exit0; evidence/legacy-final.log |
| `git diff --check 7fb2c8ef82b30ee6572119016c8bb906733c129d HEAD -- '*.py' '*.md'` | PASS exit0; checked before final seal |
| Full raw diff check | exit2 due retained original failure-log trailing whitespace; evidence/raw-diff-check.log; not sanitized |
| Original fixtures/manifests from base | unchanged, hashes/environment in evidence/ENVIRONMENT.json |
| Full repository scripts/verify.sh | prior blocked before suite by missing Flutter, ../evidence/repository-verify.log; not rerun or installed |

Python3.12.14/Linux6.18.55; existing engine candidate inventory/provenance/license evaluation unchanged. Android remote candidate f4781e16ddf4e542b983fbd77f266a0071148255 and UI69b9cc3b6c5726006363bbf2add3b2564212731b read-only checked; owned paths untouched by UI relative to fixed baseline. Original /workspace/Muyon worktree stays clean. No main/develop/Rust/Android/production UI edits, merge, force push, branch deletion or deployment.

## Exact remaining gaps and allowed source continuation

- Known failed action remains prior bwrap0.12.0 namespace setup for harmless /usr/bin/true, exit1 `setting up uid map: Read-only file system`. Environment filesystem denial, not approval-review rejection; no engine started. No retry, relocation, alternative namespace or escalation. Original ../engine-evaluation/evidence/isolation-attempt.log retained.
- Real trusted HostSession authentication, kernel HostOSBackend and worker IPC bootstrap are unimplemented/unqualified. No actual engine-entry attestation transport exists. All real no-network/RO scoped mounts/limits/reap/stable-snapshot/credential authenticity tests remain NOT_RUN; current real entry remains HOLD. FakeHostSession/FakeHostOS only exercise trusted application API contracts with synthetic objects, not genuine credentials or sandbox evidence.
- Concrete engine artifact origins/transitive/native/font license reviews and isolated real library copy/reopen/oracle compatibility remain incomplete. No third-party import/execution/installation/EULA/payment/credential/system or permission change occurred.
- Within current source-only authorization, further useful work can define bounded broker IPC envelopes/transport seams, authenticated evidence verification interfaces, scoped fake-peer cancellation/transaction tests, and broader original format fixtures with precise unsupported states. Actual sandbox operations and real engine integration require new compliant environment evidence; current denial will not be bypassed to obtain it.
- Office overall incomplete: DOCX single plain run, PPTX single plain shape, XLSX numeric single-cell remain narrow source subsets; actual serialization/reopen compatibility, render/visual/recalc/annotations/public readers/core CAS/UI integration are NOT_RUN or unimplemented. Numeric5.0→5 stays a failure. PDF remains conservative static preflight without parser/render/editor. No complete four-format editor claim.

Historical2 unknown model requests/¥0.002620 reservation untouched. No real user documents, model/search requests or external file transfer. Leader B remains sole develop merge executor.
