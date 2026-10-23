# S1 test preparation (not executable tests)

Fixed plan: `64900d4a6a46a9ef2919bcf922fb059413b1ce82` / `2026-10-23-skill-runtime.md`. All rows below are planned assertions, NOT_RUN. Exact public constructors, error envelope fields, encoding and fixture format await the parent's fixed C1 source/fixture SHA. This document neither freezes a new contract nor implements a parser/runtime.

## S1 behavioral test sequence after C1

| Group | Setup / mutation | Observable assertion | Defect caught |
| --- | --- | --- | --- |
| `catalog_is_read_only` | Only two trusted compiled descriptions plus synthetic alternate version | list/get return exact refs and declarations without Skill body, business rows or implicit execution; test invocation count remains zero using a meaningful forbidden invocation seam, not an unrelated counter | Catalog getter accidentally invokes a tool/owner or exposes business context |
| Version coexistence | Same skill ID, two distinct versions | Both exact references resolve; original reference unchanged | Lookup aliases all versions to newest |
| Digest pin | Same skill ID/version, alternate digest | Refuses ambiguous/conflicting immutable version; original ref cannot resolve substituted bytes | Digest ignored or content overwritten in place |
| Missing entry | Unknown ID, version, digest, binding ID | Error, never default-first or latest fallback | Silent fallback gives wrong content/binding |
| `binding_cas_and_upgrade` | Current binding revision and wrong expected revision | Reject; original binding unmodified | CAS compares wrong object/revision |
| Exact CAS | Expected equals current; proposed exact built-in reference changes | Valid candidate only; no persistence/dispatch; original snapshot stays unchanged | Candidate validation silently mutates current snapshot |
| Binding identity | Replacement changes binding identity, scope or bot association | Reject incompatible replacement rather than reassigning an existing binding | CAS used to transplant authority/context |
| Upgrade | Same binding to exact new skill version/digest | Only declared reference/state transition is accepted; upgrade has no grant/allowed-tools side channel | Registration/upgrade becomes permission grant |
| Disable | Candidate disables a binding | S1 returns metadata only; no new run entry point; runtime dispatch refusal is S2, not a false S1 claim | Test treats catalog success as runnable permission |
| Fixture conformance | Skills-owned synthetic fixture consumes C1 types | Roundtrip exact revisions/digests/scope; unknown authorization fields rejected under C1 policy | Skills invents parallel serialization |

Plan API has `list_skills -> Vec<SkillRef>` and `get_* -> Result`; malformed snapshot detection must use a reviewed validation boundary or rejecting getters, not silently change the public signature. Once C1 is fixed, select and record the smallest plan-compatible validation surface before test authoring. Do not add a second registry persistence owner.

S1 command (first compile-ready unavailable stub must lead to assertion failure, not unresolved symbols):

```sh
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test public_skills
cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked --test agent_workflow
```

No test body is authored until C1 arrives; there is no current RED/GREEN.

## S2 follow-up coverage (blocked; no wiring)

| Planned scenario | Required evidence |
| --- | --- |
| Malicious prompt requests write while required only read | Entire requested action rejects; no partial-success filtering, zero unauthorized dispatch |
| One of host/plugin/descriptor/connection lacks requested capability | Overall rejection; same connection in another plugin does not supply authority |
| Host grants local capabilities explicitly for local Skill | Explicit four-set intersection; empty connection set is never auto-bypass |
| Binding scope, generation, exact SkillRef or expected revision differs | Reject before dispatch; after revoke recompute per step |
| Disabled/re-enabled binding | New calls blocked, old prepared remains invalid, dispatched task remains original owner's responsibility |
| Unknown schema digest, wrong input types/bounds | capability unavailable or precise validation failure under frozen contract; only reviewed built-in schemas |
| Timeout, UI close, process restart | Same original IntentId; lookup/cancel via C2; prepare/dispatch counters unchanged by getter/recovery |

`JobSnapshot`, C2 original-result mapping, exact error fields and original workflow handoff must be supplied before these tests claim integration. A copied snapshot alone cannot prove authorization, cancellation or original-owner recovery. S3 remains a later written license/compatibility evaluation; script assets never execute.
