# Evidence index

`final-manifest.json` records fresh offline commands, timestamps, statuses and implementation/test/lock hashes. Corresponding final-*.stdout.log and final-*.stderr.log are original bytes. The final Cargo suite reports 188 passed, 0 failed; standalone runtime 20, governance 21. `historical-status.json` records older statuses and explains invalid stale output `09-projection-red.log`.

Independent reviewer report is one directory above. Independent raw final-runtime output, historical IR-01 source and RED output are archived here; `independent-ir01-evidence-note.txt` identifies the reproduction's historical input snapshot.

`toolchain.json` contains official archive URL and verified SHA256; archives, installed temporary binaries, Cargo cache and synthetic test databases are task-local `/tmp` artifacts, not committed. Existing lock dependencies only. Initial compile/cache/link failures are intentionally retained. `SHA256SUMS` covers all evidence except itself and identifies bytes for review; it is generated after verification.

NOT_RUN is recorded in REPORT.md. No real user files, model/search/provider requests, original historical unknown requests or reservations were exercised by these tests.
