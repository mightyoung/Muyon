# Service retirement ABI delta — independent review

2026-10-15. Original non-author host/UI reviewer; read-only contract review only. No source edits, builds, tests, generated bindings or Android execution. This review does not reopen the approved B design or supersede its existing findings history.

## Exact inputs and scope

- Baseline `B-SERVICE-ABI-fixed-b361.md`: SHA256 `b361f966ff15f92de762b47fbcfada2619bcfe086e2d7aa9bafd5aa1cd63aea4`.
- Candidate `B-SERVICE-ABI.md`: SHA256 `fd57f5008b87f317c172f7bc0cfd0734a70da8ef2d2c9641b375c06e75bb7eb2`.
- Existing final contract: `ANDROID-AGENT-SERVICE-SLICE.md`, reviewed SHA256 `5be6a11739f3d48153c18631ebbe9473bff7e2aa9adb7f44cc5a3ca5f8c58e18`.

Fresh SHA256 and complete unified diff inspection confirm candidate adds only the six-line late-bootstrap retirement section. Diff exit1 denotes these expected differences, not a failed review command. No product source/runtime equivalence claim is made by this document review.

## Verdict

**Retirement/build-identity design: SPEC PASS. Critical0 / Important0 / Minor1.** No important lifecycle or authority defect was found in this scoped design delta. One minor exact-ABI documentation inconsistency remains below, so the candidate is not yet reported as an entirely finding-free ABI document.

`retire_service(&self) -> AgentCloseReply` solves a real gap: late bootstrap can return an actual controller after the platform generation is retired, before any client lease exists. Reusing client-bound close would require fabricating a lease or consuming a client slot. The new method operates on the actual original controller object and thus its real epoch; it takes no caller-supplied replacement identity, does not connect a client, and remains absent from AIDL/UI. A captured old bootstrap result must retire that original object rather than a newer field value.

The stop is permanent and applies during initialization and zero-client bootstrap as well as later states. It does not bypass the sole settlement waiter: Closed still requires actual worker drop/join and RootLease release. Inherited rules keep joins off Binder/main/controller locks, preserve durable Unknown/recorded receipt precedence, and retain the execution slot until settlement. Idempotence adds no restart or cancellation-acknowledgment guarantee. Service-only here describes the application boundary; it does not claim a new security sandbox within the existing same-UID Service design.

The plain host config's trusted validated40hex build identity avoids imposing bridge build-environment requirements on ordinary host callers/tests. The shipping bridge alone injects its compile-bound identity; UI/AIDL cannot supply it. Format validation is not itself provenance: the bridge's actual build-source checks and original trusted host construction remain required. This delta does not broaden request authority, filesystem-root selection, public model data or permissions.

## Finding

**RETIRE-O1 — Minor, open at fd57.** Candidate line118 introduces a distinct `AgentServiceSetupError` for constructor failures, while line9 still specifies `new(...) -> Result<Arc<AgentServiceController>, AgentServiceError>` and line90 explicitly returns `AgentServiceError::Busy`. The new setup enum has no listed variants. Native generation, UI handling and the independent JVM checker need one unambiguous constructor error surface.

Minimal correction: specify the authoritative public constructor error type and its closed variants, then align the constructor signature and setup Busy reference. Alternatively state explicitly that the distinct setup type is internal and maps to the existing public error type. Preserve safe unit errors with no paths/exception text, unsupported protocol/root/lock/restore mappings, and the distinction between pre-controller failure and published-controller RecoveryRequired. This is routine ABI exactness, not a new user approval or architecture gate.

## Follow-through evidence

The stated zero-client native initialization-retirement target and separate UI late-bootstrap generation test are appropriate, but no results are independently asserted here. Implementation review should verify that the production Service uses this exact path, no AIDL retirement method is added, the old object cannot retire a replacement, repeated calls cannot reopen admission, and Closed/root-lock availability occurs only after genuine settlement. Existing state/receipt/Unknown rules must remain intact. Those are source/test checks for the planned implementation, not claims that this document proves behavior.

**New tests/builds/runtime runs: 0. Android process/lifecycle execution: NOT_RUN.** Continue the already authorized B task with original owners; retain the original UI source-review role for a fixed GREEN checkpoint.

## Scoped closure — af4dfd9e

Fresh hash and full diff against preserved fd57 confirm the correction is confined to the constructor signature, setup mapping paragraph and authoritative setup enum/conversion explanation. Final candidate `B-SERVICE-ABI.md` SHA256: `af4dfd9e92751e38808ff17bc55aa0eaa1668643b0329232a5286e79ed7fee9b`.

**RETIRE-O1 — CLOSED.** Public new consistently returns AgentServiceSetupError with five unit variants: UnsupportedProtocol, InvalidRoot, Busy, RecoveryRequired, InternalFailure. The internal host error maps its first four corresponding cases directly and other setup failures to safe InternalFailure. Business/control reply errors remain separate. Invalid trusted source identity cannot become caller-selected provenance or an exception string. Desired root/storage/lock behavior is explicitly a GREEN requirement rather than an assertion that the current refusing checkpoint implements it. The referenced implementation lines are author-provided context; this narrow document closure does not independently review that product checkpoint.

**Final scoped verdict: SPEC PASS / QUALITY C0; Critical0 / Important0 / Minor0 open.** Retirement semantics remain unchanged from reviewed fd57. No source modifications, new tests/builds or runtime runs were performed. The approved original-owner development can continue without another permission gate; actual implementation/Android evidence remains subject to its separate reviews and gates.
