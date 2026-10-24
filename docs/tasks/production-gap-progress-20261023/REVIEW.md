# Independent review record

2026-10-23. Scope: the new Rust persistence, host adapter/session and GitHub response adapter on develop e16af808.

The core code reviewer approved the persistence slice after correcting historical-marker replay: an existing SaveAck must restore query-only state, not return another dispatch command. The regression uses two old editor copies and the same save intent.

The host adapter implementer independently reviewed the session and found an execution-before-binding-check defect. The final session compares its full command against the original owner's prepared command before saving a marker or confirming. The unrestricted mutable editor accessor was removed. A domain-valid altered grant now produces no marker, no dispatch and no project.

The integrator reviewed the GitHub adapter and required actual tested-subject evidence separate from Actions head_sha. The final adapter binds trusted observations to workflow/run/attempt and head/base, retains TestMerge separately and leaves unknown subjects Unknown. The real read-only response probe supplies no checkout attestation and correctly produces Unknown with zero checks.

The independent architect reviewed all four implementations and original SQLite/owner/reducer paths: WATCH, no remaining must-fix correctness or authorization blocker for this Rust slice. The architecture conclusion is explicitly limited to the implemented host seams, not full product acceptance. Recovery may seal a not-yet-confirmed review before a concurrent confirmation; the existing owner contract deliberately prioritizes that conservative recovery ordering.

Remaining integration responsibilities: the actual host must derive trusted account/scope generations, retire sessions on changes and keep confirmation in visible review callbacks. The repository host must obtain independently verified checkout provenance and current access. No Android UI or model tool is newly registered here; no OAuth/WebHook, Reader/FD, device or visual gate is closed by this review.
