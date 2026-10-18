# SDD ledger — plan: docs/tasks/service-lifecycle-failures-20261018/PLAN.md

Task 1 pending; Task 2 pending. Base 7f783eb5cadef65720f8788b077858372f419b62.

| Pair/task | Produces/consumes | Preflight finding |
|---|---|---|
| Task1 / Task2 | source + exact workflow / reviewed scoped execution | Reviewer must approve call graph before execution; no overlap writes |
| Task1 | named failure tests / real Service lifetime fix | Contract permits compiled hooks only, no production authority |
| Task2 | reviewed frozen SHA / CI evidence | dedicated lab trigger only; failures preserved |

Ruling: use the clean task-specific lab branch in the supplied checkout rather than creating another checkout — this environment has no other writer and user authorized a new branch; incorrect occupancy would require re-isolation. Remote open PRs and branch refs were checked before edits.
