# A — Android minimum API26

Product branch `task/leaderb-min26-20261018`; fixed source `3f3a2368648db5e9767f11adcae4548ac5da2527` (commits136477f4, e49be079,3f3a2368), based on A `7965f46beba6f52924e73e99fde6d69c18d985ff`. Pushed; working tree clean. No develop/main integration.

## Delivered behavior

The shipping Flutter app and independent lab explicitly require Android8/API26. Native producer clang/stubs/ELF note, strict V2 input schema/verifier and APK controls agree. V2 uses format_version2/min_api26 while preserving protocol1 and the existing field/identity/hash requirements. Original V1 docs/schema and dated API24 records are unchanged history. Current diagnostic has an explicit dated supersession note. The source manifest now tracks V2/schema/new workflow. Shared entry Gradle edits were notified to the integrator; no Compose pages/resources or OCR module was edited. Compile/targetSDK declarations and permissions are unchanged.

This source builds the existing Flutter/Dart application for Android8+, not a new UI/Service/store business loop. ReceiptObserver remains default-disabled. No APK installation, Android8 runtime, real database migration, OCR integration or I04 action was executed. UI polish is paused per parent; minimal frontend/backend integration is next-session work, not added here.

## Exact source build

Required Android CI [39102166352](https://github.com/mightyoung/Muyon/actions/runs/39102166352): completed/success, all four jobs. Shipping release APK191.8MB (rounded Flutter log), SHA256 `6ed859f31c89479e2fb2f0a0c5a116278869c759b71e4a0d09d601c689676c49`; actual aapt badging minSdk26/targetSdk36. Shipping receipt observer actual-class check and lintRelease passed; lock equality check passed. Lab source compilation/lint/state checks passed without optional native inputs. Fresh arm64/x86 Rust links and exact API26 import-stub/ELF checks passed. Combined optional-native lab APK packaging was not run; these separate checks do not establish App/Service/native runtime integration.

Four CI evidence artifacts are present/nonexpired at readback (logs/lab/native evidence). The release APK itself was not retained/uploaded; its provenance/hash/minSDK are in the complete raw log. No installed application delivery is claimed.

Independent review at exact3f3a2368 and author71 strict packaging controls passed; see record reviews/contract-and-min26-review.md and a-review-manifest-3f3a2368.json. Source diff check passes.

Generic CI39102166368: PENDING at this draft; must read terminal before closing.

## Preserved failures and cancellation

Original e49be079 Android CI39101690023 failed shipping Java compilation: generated GeneratedPluginRegistrant referenced dev-only integration_test, excluded from release Gradle. Flutter3.47.5 source proves `--no-pub` skips release tooling regeneration; prior pub get left dev-inclusive registry. Minimal3f3a2368 workflow fix removes --no-pub from the release build and checks lock equality. No generated code edit, devdep removal, assertion relaxation or targetSDK change. Complete original red, SDK mechanism excerpts/hashes and new green are separate evidence.

Superseded136477f4 Android39101615298 was explicitly cancelled after snapshot (native jobs had succeeded; shipping/lab cancelled). Generic136477f4/39101615134 and e49be079/39101690016 were cancelled by branch concurrency before requested cancellation, which returned already completed. They are cancellations, not source failures or current proof. Original snapshots and raw logs remain archived.

I04 stays NOT_RUN/BLOCKED and PR86/dependent integration remains held. No REMORY/RSI change. Product writers/local build/watch processes are stopped; only current generic CI and bounded read-only lookups remain at this draft.
