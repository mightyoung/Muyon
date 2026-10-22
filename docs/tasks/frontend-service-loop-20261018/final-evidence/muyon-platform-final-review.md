# Scoped platform acceptance source review

Fixed source: `98923e71ef1e89f653dc18031e09c734c474c1bb`; reviewed only code changes from `2a763bdf907d0068d4cd5ad2e8492aeb8fbfe9ac` (workflow and FrontendServiceLoopTest). Other differences are retained documentation/evidence. No commands ran tests, killed processes, invoked providers/models, or touched branches.

**No new blocking issue found in this scoped diff.**

- Instrumentation obtains the application's exact `${context.packageName}:agent` process, asserts same UID and distinct UI PID, repeats these checks immediately before `Process.killProcess`, and targets only that PID. It does not kill a package globally or affect a named unrelated process.
- Recovery uses the real existing Activity/Application/private Service path. It waits for UNKNOWN, hidden current receipt/projection, preserved historical original receipt identity and disabled Send; it then clicks only the existing reconciliation control. It neither installs a fake port nor clicks Send again. The recovered original receipt identity and invocation_id must match, supplier projection must return, and a new same-UID distinct Service PID must exist. These are meaningful runtime assertions, not synthetic success output; their execution result is still pending.
- UniFFI generation now executes from the bridge crate while retaining absolute library/target/output paths and the same pinned config. The subshell preserves the workflow root for subsequent generated-source cmp. The code change matches the cwd requirement described by the parent; its reported local cmp PASS was not rerun here.
- The added Rust unit command uses the exact supplier_business::terminal_regressions filter and asserts three passing cases. It does not execute the unrelated HTTP/reopen module. Existing explicitly named integration targets remain scoped.
- Workflow push trigger remains the isolated lab branch, contents permission remains read, and no merge/main/develop write/deploy step is introduced.

Proceed to collecting the exact-SHA combined CI/API26 result. This read-only review does not itself establish Android runtime recovery success or real model/production-store use; those claims remain bounded by actual evidence and existing holds.
