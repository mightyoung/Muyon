# UI-4a code implementation

Base: 5afb08f2b0d53ca5d8578e63073fea6ac385a8af. Task: docs/tasks/UI-4a.md.

Cloud deployment/browser acceptance is paused by the user. This slice implements and tests the code/build boundary only. No REG-4a dependency or host authorization replacement; business preview is explicitly simulated.

1. RED: invalid components retain mandatory fact states and original source; atomic complete/duplicate/stale patch and edited-input preservation.
2. GREEN: typed node-only patches; validate the complete candidate before accepting; preserve current validated plan and stable node state.
3. RED/GREEN: local edit/sort/source/back, guarded business and semantic event sinks; receipt only from the attached port; no plan-supplied status or permission.
4. Map existing layout/confirmation components and minimal table/field/source adapters; preview public fixtures exercise confirmation/cancellation.
5. Run targeted and existing package suites, analyze and Web release build; independent review, fix findings, commit task branch, remote SHA and exact CI.

Deferred: controlled URL, real cloud browser smoke/screenshots, REG-4a business catalog integration, real native database writes/OCR/permissions/device capabilities. UI-3b persistence and UI-4b providers remain separate tasks.
