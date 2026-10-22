# Revision progression follow-up

Parent independent static review found an Important correctness defect in source
9b242a4ae0143b872e7c885be29585da87a165f8 (delivered with evidence af24d63e30109812380fc05b59b1bb8e29cf47c3):
accept_commit only rejected equality, so a trusted-host receipt with a lower output
Revision could incorrectly enter Committed and become an Export/rollback base.
This was a contract-validation error; no real publication or Office engine exists.
The previous independent review did not identify it; earlier test totals are retained
as historical results and do not establish this invariant.

Shared contract::Revision is numeric u64 with checked `next()`. Existing BusinessStore
publication uses expected_revision.next() (business.rs429/600). The corrected
common accept_commit path requires exactly previous_revision.next(), not string
comparison or merely non-equality. Overflow maps to Error::Binding. No receipt/state
is installed on progression rejection. Direct Commit, Unknown RecoverCommit and
cancelled late RecoverCommit all pass through the same check. Rollback remains a
new transaction and must publish a new increasing revision; restoring old content
does not move the revision counter backward.

Test-first behavioral RED is preserved in evidence/31-revision-regression-red.log:
base1 -> output0 was erroneously Ok. The added regression checks9 source/output
pairs through all3 entry routes: same value, 1->0, 9->2, skipped1->3, valid0->1,
9->10, MAX-1->MAX, invalidMAX->0 and MAX->MAX. Rejections preserve the pre-existing
Validated/Unknown/Cancelled state and candidate and cannot Export or form a rollback
base. This is27 assertion scenarios within one test function, not27 extra tests.

Final offline validation remains on exact core ab9c381cc935be0cd52db5a8a455ce985bdba1db
in the temporary combination, without changing lib.rs or documents/. Raw focused
results: evidence/32-revision-fixed-green.log. Full core: evidence/33-revision-full-core.log.
Negative controls include reverting the revision check to old non-equality, compiled
then caught by the new behavior assertion: evidence/34-revision-mutations.log.
Final non-author review, probe results and source hashes are recorded separately.

Scope: one production validator plus corresponding tests/docs/evidence. No real
file write, model/search/network request, permission/DB/UI integration, deployment,
main/develop modification or old unknown-request replay in this follow-up.


Fix source commit: `84d438e3f2587c3398c33fac7e984cd5143289a0`.
Final focused28+18 tests and complete muyon-core193 tests passed,0 failures and
0 compiler warnings;7/7 negative-control mutations caught. Independent reviewer
round4 personally reran28+18 plus3 probes (546 numeric/route combinations and15
max/skip edge cases), with no remaining blockers. It also verifies rejected receipts
leave state/candidate unchanged and that a subsequent legal next receipt still works.
All evidence is in evidence/independent-round4/ and logs31–34. The original review's
miss and the original failing RED are retained, not replaced by the new green result.

Final source SHA256:
- module `b8ec7dcbdb5391f7fa6e0e07c4392168a3500d3f0aa0f12aef9be0a13715f493`
- test `e1a5aa47fd434c686b5736f1e9a9a94dd7d283fc06d07bb2c059727178383b38`

Full workspace MSRV1.91 and missing Flutter blockers remain unchanged. This fix
still validates only host observations and does not implement actual publication.
