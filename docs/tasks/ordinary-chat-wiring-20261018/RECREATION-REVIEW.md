# Independent recreation repair review

Reviewer: independent_review subagent; base
0345822d919411b17f5c082c362e03da66d55290. Reviewed lifecycle/state/Service lookup
source and the new-run failure, then separately reviewed the test-only correction
and standalone policy probe. No network or old suite execution by reviewer.

Diagnosis: Disabled follows the existing explicit recovery contract: onStop ->
last visibility false -> transportLost -> unknown/hidden disclosure; unknown
cannot send. The failing test omitted original-request reconciliation. Static
lookup inspection found no inevitable cross-epoch rejection; runtime still needs
verification.

Approved with no blocking findings. Waiting for UNBOUND plus the existing final
stop/unbind publication avoids treating synchronous release as stop completion.
No arbitrary delay is used. The real existing query button is clicked once;
Service/Rust is not bypassed. Unknown nonblank Send denial, hidden disclosure,
identity and attempt checks are added. Recovered answer/identity checks precede
the original unweakened second-send and quota-denial assertions.

Reviewer independently executed only the already compiled standalone policy jar:
PASS. It explicitly proves presentation policy only, not Android/Binder recovery.
New CI must establish actual reconnect/lookup/disclosure and second-send behavior;
retain failure without automatically rerunning.
