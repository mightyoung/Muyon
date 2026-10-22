# Archive download denied — not retried

Action: `gh run download 39127896088 --repo mightyoung/Muyon --name service-durable-owner-evidence-39127896088-1 --dir /tmp/muyon-owner-green-artifact`.
Target: the named GitHub Actions artifact, remote artifact storage.
Outcome: **DENIED / not downloaded**, HTTP `403 Forbidden` from the signed artifact-storage URL. This is a remote download denial, not an automatic approval-review rejection. No alternate path, connector, environment or retry was attempted. The temporary signed URL is intentionally not reproduced.

Already completed independently before the denial: `gh run view --log` retrieved the full final execution log to `/tmp/muyon-39127896088.log`; terminal run JSON confirms success at d28e8d3ed08d2185198284794dd116e3d6eb3290. Those obtained logs/JSON are retained in evidence/. Actual log shows BUILD SUCCESSFUL and OK (17 tests). The downloadable archive copy remains unavailable; its absence does not turn the obtained execution logs into archive evidence.
