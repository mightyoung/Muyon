# Independent review record

Reviewer `design_review` was independent of component writer `canary_budget` and leader/reference-renderer writer. Reviewer changed no files and made no model requests.

## Design gate

REJECT for complete real integration. The initial short design lacked an executable live evidence migration, guarded network handoff/cancellation acknowledgement, Service-process credential composition and concrete hosted token/currency proof. The reviewer explicitly allowed only isolated immutable configuration/pricing/batch-ledger/token-proof preparation. DESIGN.md records the required repairs. This gate has not been converted into live approval.

## Component review, first pass

REJECT. Found that success could atomically replace the ledger and then fail directory fsync, return Refused but leave success visible, allowing a subsequent reservation. Also found mutable verifier input could differ from the bytes initially hashed. Requested real multi-process/crash/fault tests. The original eight-group runner passed but did not prove these boundaries.

## Repairs and final component pass

OKAY, limited to the independent offline components. Every mutation first establishes a durable in-progress marker. Marker recovery under the exclusive file lock changes entries to unknown and permanently stops the batch, retaining reservations. Ledger file/directory durability and temporary cleanup precede marker deletion; no fallible I/O follows successful deletion in the mutation. Channel/lock cleanup does not turn a durable success into an uncertain result. Verifier gets a copy and mutation is rejected. Fee input was renamed reportedFeeMicroCny and explicitly remains caller-reported, not a verified invoice.

Reviewer independently ran:

`sh experiments/redesign/android-compose-lab/checks/run_ordinary_chat_canary_budget.sh`

Exit 0: 11 budget groups plus the reference renderer's four official fixtures/history/Unicode/rejection checks. Includes three injected persistence failures, a forcibly killed pending child process and two concurrent child processes. Zero network requests. The leader independently ran the same final runner with exit 0. Shell syntax and final staged diff checks are separate validation.

The reference renderer was independently checked by `official_pricing` against its already-inspected pinned official encoder: strict role subset, markers and 71/94/217/141 UTF-8 upper-bound fixtures agreed. Its requested Unicode exact-string assertion was added. This was reference-model verification, not hosted billing parity.

Android filesystem behavior, actual owner/ABI/HTTPS/credentials, actual provider usage and hosted billing proof remain outside approval. No review authorizes opening the live gate.
