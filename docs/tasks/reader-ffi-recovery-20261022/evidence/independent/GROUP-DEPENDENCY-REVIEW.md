# Independent Group dependency recheck

Read ADAPTATION.md, fixed5f2644cfbcc580a0cc9a567c5272d58c35b47ac3 Group gate,
namespace initializer and canonical binding initializer; inspected current Core
exports, workflow open and absence of the proposed gate/origin/binding additions.
Source hashes are in group-dependency-source-record.json. No Rust tests rerun.

Conclusion: the stated dependency HOLD is justified; no Important error or
unnecessary authorization restriction was found in that conclusion.

- request_local_group_evidence returns Ok(false) when its nine-table name set is
  empty. group_request_gate can then produce group_hold=false for genuine Direct
  origin only if its other origin, ledger and actual-Group-evidence checks also
  permit that classification. Absence alone never means permission. ADAPTATION's
  wording that Direct CAN be classified nongroup is accurate, not a guarantee.
- initialize_group_runtime creates an absent namespace and can perform its
  explicit version migration. initialize_group_request_bindings creates an absent
  canonical namespace. Neither is an appropriate no-write integrity probe for an
  existing workspace where complete loss must cause HOLD.
- Current develop lacks the fixed gate/request-origin/canonical association
  integration. A public Group-owner hook using the SAME owned connection to
  validate full required DDL and exact workspace/version is a reasonable denial
  prerequisite. It does not itself authorize execution or replace ordinary
  configuration, account/project, proof, budget, original attempt and claim checks.
- RunLedger::open detects a missing file and opens SQLite with create enabled;
  it builds the fresh schema when missing. Do not use it as a missing-ledger probe.

Implementation caveat: a one-time path existence check before create-capable
RunLedger::open has a check/open race and cannot establish detection of deletion
AFTER an existing connection opens. To meet the proposed negative cases, require
an owner-level open-existing/liveness contract or equivalent owner-controlled
validation. This is a future implementation dependency, not a defect in an
implemented gate: no such source has been added in this checkpoint.

The full-namespace prerequisite is deliberately conservative. It may HOLD a
legitimate old Direct workspace whose extension was never initialized; it cannot
infer whether absence means never initialized or lost historical Group data.
Explicit NEW registration or owner-approved migration must resolve that state;
request dispatch must not manufacture an empty namespace to turn HOLD into Direct.

No initializer, second database, SQL policy reimplementation, production mutation,
old-branch merge, provider/model execution or authorization test was performed.
The parent's baseline cargo/clippy runs remain separate from this source inspection
and the earlier independent standalone8 helper tests.
