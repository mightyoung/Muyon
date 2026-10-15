# Independent Rust Agent process checks

Run against an actual compiled `muyon-core-agent-lab` from repository root:

```sh
python3 -B experiments/redesign/core-agent-lab/checks/process.py --binary experiments/redesign/core-agent-lab/core/target/release/muyon-core-agent-lab --evidence-dir /tmp/core-agent-process-evidence
```

Python standard library only. No model calls, endpoints, dependency installation,
Rust source substitution or P07 implementation. This checker calls the documented
CLI, observes actual key=value results and independently reads physical
CORE_EFFECT_V1 receipt rows/counts/value. It does not implement an Agent, policy,
business transaction, receipt issuer or model simulator. The Rust fixture provider
reads the input-only TSV events itself.

SIGKILL tests wait on flushed `checkpoint=dispatch|effect|projection` notifications
with a bounded selector. There is no sleep-based race. Effect and original receipt
share one atomic store boundary; the checker does not invent a separate nonatomic
receipt checkpoint. Cancellation uses a separate actual process while the running
kernel holds its lock. Private synthetic directories, command transcripts and
physical files remain in the external evidence directory. Missing/corrupt effect
stores are preserved as test evidence and never repaired by the checker.

The complete command fails when any required process check fails. Missing binary,
timeouts and setup errors are errors, not behavior RED or passing evidence. The
workflow always requires this checker after offline Rust tests and release build;
there is no conditional final skip. The first intentional Rust RED checkpoint
fails before reaching this checker, and must be reported separately.

Identity and summary JSON include exact checkout SHA, actual binary SHA256, fixture
hashes, named method/failure/error counts. Initial expected outcomes and provider
inputs were authored before implementation inspection. A fresh non-author reviewer
must review both writers' final source and the combination. M03, production issuer,
real models/network, power-loss, native/platform and remote exactly-once guarantees
are outside this isolated experiment.
