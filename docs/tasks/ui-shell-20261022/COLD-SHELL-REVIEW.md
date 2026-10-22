# Cold shell independent review

Reviewer `/root/review_shell`, 2026-10-22 UTC. Reviewed base `9b5abdc3f13b2a70df244ced07b089ac5cf576b5` plus current uncommitted shell projection/UI/test changes against the authorized host dependency `1b097e3b519f74dad462390dabe8cd05e942c0ab`. Exact input SHA256, command and directly captured stdout/exit are in [cold-shell-independent.log](evidence/cold-shell-independent.log). Input hashes were unchanged before/after the independent execution.

## Actual independent execution

`run-host-shell-checks.sh` compiled real Runtime/reducer/archive/codec/session and shell consumers with Kotlin2.2.20 `-Werror` JVM17, using the actual org.json artifact. Controller, request-candidate and cold persistence projection mains all PASS, exit0. `git diff --check` PASS. This fresh post-coherence-fix run supersedes the earlier independent GREEN; the parent retains [cold-shell-coherence-red.log](evidence/cold-shell-coherence-red.log) as the behavioral failure before rejecting simultaneous pending+terminal same-attempt facts.

The cold fixture uses canonical real archive and actual Runtime/codec/session; only the private boundary records are synthetic. Its test port is explicitly verified=true solely inside the test. Native business calls, transport, prepare and save throw if called. Open/read leave original lookup count0; one explicit fixture-only query observes the original, and subsequent shell read does not add another lookup. This is not an actual native save or production verification gate release.

## Static invariants checked

- Decoder checks exact outer setup scope/draft/CAS, canonical stored decimal/UUID values, fixed finite history keys, base+1 proposed revision and committed revision consistency.
- Pending original attempt cannot simultaneously be the terminal outcome. Unknown cannot report Saved or enable save/restore. Stored0 cannot claim restore support.
- Cold history cannot acknowledge the mounted editor, even when old/new memory/editor counters both equal0. A live acknowledgement must match exact mounted memory/editor and committed stored revisions; unsent UI buffers still prevent a visible Saved claim.
- Historical noncommit proposed revision is labelled as a plan rather than a committed store revision. Store cursor cannot regress; same-attempt terminal facts cannot reverse, vanish or become a different cold/live record. Same memory CAS permits only storage observation changes while canonical editing content remains identical.
- Persistence operations may appear as passive host facts, but save/restore/query_original_save are still excluded from controller mutation allowlist. All three UI persistence buttons remain disabled; formal creation/start remains disabled. Ordinary read does not reconcile the original save fence.
- Actual Service verified=false and unavailable prepare gate remain untouched. No Runtime/Service source was modified by this reviewer.

No outstanding Important issue was identified in this bounded final review.

## Evidence boundaries

The shell does not receive full native namespace/registry/archive-digest binding in the display outcome; that validation belongs to the trusted host codec/session, so this review does not call shell display a complete storage proof. A historical result is not a current editor save, and plain reading is not original-attempt reconciliation. The live Saved mutation in the test is an explicit negative/positive decoder fixture, not a real host persistence success.

Android compilation, Compose layout, actual Activity/IME/Back/lifecycle and Service/native durable behavior are not executed here. Existing AGP/toolchain failures remain. This source-only display adoption does not open local saves, restore, original-save lookup, public reader authority or real model/search requests.
