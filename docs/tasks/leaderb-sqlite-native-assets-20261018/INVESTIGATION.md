# Host SQLite native assets: bounded investigation

Original B `379b1a6d8d5a5830fb3a74924fd5c41cfb234e1c` CI [39099707674](https://github.com/mightyoung/Muyon/actions/runs/39099707674) remains failed. A `7965f46beba6f52924e73e99fde6d69c18d985ff` CI [39099985492](https://github.com/mightyoung/Muyon/actions/runs/39099985492) remains independently successful. Neither historical result is replaced or waived.

Both logs show runner image Ubuntu24.04 `20261012.334.1`, Flutter revision `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`, identical Flutter/pub cache keys and **cache misses** for both. The comparison of root manifests/lock, host Dart lib/tests, generic CI script/workflow is empty (`evidence/a-b-inputs.diff`). No evidence supports different restored caches as the cause. Native generated artifacts were not uploaded in either historical run, so their hashes/loading manifests cannot now be recovered from those logs.

B failed at `StorageManager.open`, before TLS business assertions. The engine reported **No available native assets**, then failed process fallback for `sqlite3_initialize`. This differs from finding an asset whose `.so` is missing or lacks a symbol. Other SQLite tests in the same host run succeeded.

## Established shared-writer mechanism

The only nested Flutter launcher in host tests is `_child` in `le06_recovery_independent_test.dart`. Its children previously ran `flutter test` in the parent's current project. These synthetic local-export ledger tests use SQLite triggers, completion/cancellation and two independent-process reservation contenders. They do not exercise the denied I04 legacy-provider/HTTP/reopen action.

At exact Flutter revision above:

- [test.dart](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter_tools/lib/src/commands/test.dart#L502) builds native hooks, then copies the result to the shared `build/unit_test_assets/NativeAssetsManifest.json` at line527 on every invocation. Copy is an overwrite, without an atomic publish or a lock shared with the outer test processes.
- Its asset rebuild at line812 calls [writeBundle](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter_tools/lib/src/bundle_builder.dart#L145), which deletes/recreates the same asset directory when rebuild is required.
- [native_assets.cc](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/engine/src/flutter/assets/native_assets.cc#L104) loads `NativeAssetsManifest.json` from the asset store as each engine starts. A missing/malformed manifest registers no mappings. An empty registry produces B's exact “No available native assets” diagnostic.
- The native hook build also rewrites `build/native_assets/linux/native_assets.json` before the copy; generated compiler/native outputs were shared too.

A regression launches the actual LE06 Flutter child and checks that the parent's native manifest remains byte- and modification-time identical. Before isolation, the child exits successfully but the assertion fails: parent mtime `05:48:13.253720` becomes `05:48:21.905699`. Raw expected semantic RED is `manifest-regression-red-proxy.log`/exit1. This deterministically proves the shared overwrite. Initial setup failures and an incomplete isolation attempt (missing package_graph.json) remain separate raw logs; they are not semantic REDs.

This is a source-established race mechanism consistent with the original B symptom. The original missing-manifest read was not instrumented or captured; historical attribution remains an inference. No re-run success is presented as a root-cause diagnosis or proof of zero flake.

## Narrow fix and limits

Each LE06 child now receives a disposable project directory, a copied pubspec without workspace resolution, private package_config with only `muyon` root remapped and other package roots resolved absolutely, copied package graph and copied native-hook download bytes. Source/test/assets symlinks reuse only source inputs. All build/cache/native manifests and installed shared libraries are generated inside the child's own directory. No pub get, production code, test exclusions, relaxed business assertions or global concurrency reduction is introduced. Parent test teardown terminates each child before removing its project.

The existing database fixture and cross-process contention semantics are retained. These changes concern host test build isolation; they do not repair or claim production App/Service wiring, a user database migration, or TLS behavior on a device. Windows symlink behavior is not accepted here.

SDK release archive endpoints returned404 in this environment. Exact Flutter tag clone succeeded; bootstrap downloaded its pinned engine/Dart3.13.4. Writable XDG_CONFIG_HOME and CI=true were needed for tool/analytics state under the restricted filesystem. Native hook downloads needed the environment proxy for initial warm-up; subsequent relevant runs clear proxies for localhost testing. No credentials, licenses, permission settings or target SDK changed.

I04 remains BLOCKED/DENIED_BEFORE_EXECUTION; no retry, rewrite, split, tool substitution, or dependent merge occurred. PR86/develop integration stays held.
