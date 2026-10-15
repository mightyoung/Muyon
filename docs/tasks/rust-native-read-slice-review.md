# Rust native registered-read slice: review record

This experimental branch starts at develop `3836149416020a0ac58f9e7ca788c20e66688e0e` and imports only the reviewed Rust component trees plus native composition work. The paused Dart checkpoint is preserved separately and is not an ancestor. This record does not authorize a merge or freeze M03 interfaces.

## Implemented boundary

The existing Agent drive loop uses generic ports. A Rust composition host owns installed Rust read handlers, synthetic physical data, current authority, original durable receipts, and final model-payload admission. A real plugin child provides catalog, ticket and schema admission. Research, inquiry, equipment and a seeded renamed mapping use the same offline two-turn protocol. Arbitrary business-handler execution in plugin children and production database migration remain outside this slice.

## Independent review and observed execution

- Core fixed `9d6b2a15ed35259d01035cdb3a53aa1586503879`: 94 tests passed, scoped SPEC/QUALITY pass.
- Plugin mapping fixed `8c389111252d7832e3a6d998d77c8ddfaa6c89a7`: 21 tests passed, scoped SPEC/QUALITY pass.
- Host fixed `5fc2b42b33901123e3f832e4458666ef5fecee0c`: 25 tests and independent physical boundary reprobes passed, scoped SPEC/QUALITY pass. Earlier review findings covered selected-record scope, fresh authority and cancellation, malformed restoration, and store write/reopen compatibility. The final candidate is parsed before atomic replacement, including the depth boundary.
- Diagnostic-only fixed `5d89c88b726a8232ba69f8d35a48a71effdb3141`: independent bounded-input, lazy-diagnostic and sentinel controls passed; all 18 original test methods remain unchanged.

Compiled RED evidence is preserved in Actions runs [38704802334](https://github.com/mightyoung/Muyon/actions/runs/38704802334) (Core, protocol, mapping) and [38705753832](https://github.com/mightyoung/Muyon/actions/runs/38705753832) (real-child host). The earlier placeholder is not treated as behavioral RED.

Normal Actions [38709397032](https://github.com/mightyoung/Muyon/actions/runs/38709397032) at exact integration `4692702fa89ffd836e0fc608ac22d963a2757887` completed successfully: Core94, plugin21, host25, physical-process44, checker13, and 17 existing compiled semantic inverses. That run predates the diagnostic safety correction and new three-native-inverse checker. These new inverses separately require physical prehandler revocation, selected-record scope, and final model-send admission; their actual baseline and mutation results require a later successful normal run. Existing 17 inverses are not evidence for these three guards.

## Evidence limits

One earlier remote CRLF seven-byte-read case failed, with a subsequent aggregate failure caused by the missing successful case. Its root cause remains UNKNOWN; no deadline or assertion was relaxed. A separate interim local directory-lock failure also remains UNKNOWN. Later passes do not establish either cause. A local legacy-mutation batch exhausted disk and is INVALID; completed remote evidence is recorded separately. Raw logs, private mutations and tool outputs remain outside Git.

The store has an explicit experimental 64 KiB limit. A post-handler persistence failure retains the original running/unknown state without automatic replay or model projection. All traffic and records here are synthetic/offline. There is no real model, credential, business database, Android runtime, or deployment evidence. Android Compose work is independently tracked in PR79 and is not connected to this host yet.
