# Raw-output whitespace disposition

The final `git diff --cached --check` returned exit2 solely for trailing whitespace/blank EOF lines inside preserved raw `.log` artifacts (see archive-raw-whitespace.log). These bytes are intentionally retained and covered by the evidence manifest; editing them would cease to preserve raw output. No source/test assertion was changed to obtain a pass. The archive check is not reported as globally whitespace-clean.

Verification scoped to authored source/docs, explicitly excluding only raw evidence `*.log`, passes:

```sh
git diff --cached --check -- . ':(exclude)docs/tasks/hy-memory-governance-20261018/evidence/*.log'
```

Fixed-source cargo fmt checks and suites remain unchanged and passed before this documentation-only archive step.
