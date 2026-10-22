# Exact native policy handoff — independent static review

Reviewed source checkpoint2a8c10b6a7314a38fbfd8fc2b73343961e317a9a.
NATIVE-READER-POLICY-V1.md SHA256:
120a6a53b07169ac31e4798b4d42b50d26cb1259c4d59b74b7012260617639c1.
Independent original output: evidence/reader-policy-v1-handoff-independent.log.

Initial875e7c350d9587c64aaa52f7677164be524e0ba0 six-endpoint contract had
Important: renew grant generation makes old presentation stale; consumed selection
ID cannot reopen it. Review evidence points to document_bridge.rs678+ and core
reader.rs478. This finding is retained; initial six endpoints are insufficient.

Corrected required protocol has SEVEN endpoints. B binds a genuine initial native
presentation opened with an actual valid existing parent grant. D creates an
exclusive native child grant on first renewal, then renews only owned child chain;
no arbitrary parent overwrites or inferred exclusive ownership. Parent revoke /
external generation changes fence derived roots under same transaction. G is a
NEW real core/FFI presentation continuation handoff: exact root/original selection/
renew attempt/predecessor frame/new grant binding, bounded one-use token, native
pre-call refusal of late A before destructive open/closing B, genuine new ticket.
Grant-issued vs handoff-pending/failed/unknown outcomes are separate; no fictional
SQL/PFD atomicity or reused old selection token. Caller still must dispose old output
and route exact invalidations in shared batch before publishing new frame.

Independent final conclusion: original Important closed at PROTOCOL level; no new
Important in bounded static document review. NO new native/runtime/device tests were
run for this proposed policy API; none of these seven endpoints is yet generated or
implemented. Host source checkpoint66394026000d3acdc4942df1df31400a8603adaa and its
real7-method transport/batch tests remain separately evidenced in
NATIVE-PRESENTATION-CONSUMER.md. Those are not policy endpoint implementation tests.

Core ticket handoff/root revoke hooks, FFI records/endpoints, Host controller/native
root+surface binding, authenticated catalog, actual PFD renderer cleanup and Android
>30s acceptance remain PENDING, not denied. Actual Activity adapterc0c2 exists but
still unattached; verified=false. Native backend development itself needs no new
user authorization. Only FIRST access with no valid existing permission has a
separate product policy choice; narrow local explicit selection recommendation is
in protocol section6. Project selection is never universal document permission.

Administrative stop/reconcile must use actual retained original root-owner records
under Service/native owner, even after active reader scope dies. They must not depend
on obtaining a new live UI principal/visibility sample after background. No public
JSON allow route, no cross-client root adoption, no resurrection of access from an
old historical receipt. The current private Host factory/permit source is a starting
point, not a completed lifecycle administration or IPC implementation.
