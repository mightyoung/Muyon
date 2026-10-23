# Shell UI candidate

Base: `7aa852ab8134545c6312cd71de5c12cd49f66b5b`.
Initial source: `ef24ce11ed1b99e2be6938b18ff5f195cc8253b1`.
Final production source: `d61be4b50c3f4877022008e5493ade1ba78a96ad`.

## Changes

- Header conversation actions have a header anchor and a distinct accessible purpose; the input plus has its own unavailable attachment menu. Existing conversation actions retain their callbacks and gates.
- Settings fields precede detailed prose. Existing scrolling remains; the original implementation was already scrollable. Details expand locally, while accounting and unknown-result budget retention remain visible. Confirmation/filtering/credential-clearing logic stays in the original host.
- Actual main/pinned conversations use a horizontal top rail; ordinary conversations remain below. Main identity uses the original mascot with Fit and no tint. No synthetic conversations or business states enter production.
- Existing Bot steps have Chinese display labels and clearer in-memory-draft wording; persistence, creation and execution gates remain closed.
- Neutral shell surfaces explicitly use theme content roles. Equal theme container colors must not infer an error foreground for a normal conversation or attachment action. Shared tokens are unchanged.

## Executed validation

The actual project sources and every androidTest source were compiled using the existing official cached toolchain:

```
gradle --offline --no-daemon --console=plain --init-script <authorized-local-repository-init> \
  -p apps/muyon_android -PmuyonProductNativeInputs=<existing-native-inputs> \
  -PmuyonModelAssets=<verified-existing-model-assets> \
  :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:lintDebug
```

Result: exit 0. This is compilation/lint, not a newly built product APK; cached native/model inputs were used without making a new native/build-identity claim. Warnings include unwritable analytics settings and SDK XML v3/v4 parsing compatibility. They were retained, not suppressed.

Neighboring offline checks all exited 0 using Kotlin 2.2.20/JDK17: shell snapshots; host controller/request-candidate/cold-persistence projection; configuration 5/5; Bot setup 17 checks; palette contrast 1/1. No provider or Reader Core operation was invoked.

Behavioral RED records precede the respective changes: missing independent action purpose (1 failure of 7), vertical pinned layout instead of a shared rail (1/1), and missing neutral theme-ink pixels on the composer action (1/1). Original failure logs are preserved. Initial 9- and 10-test component runs and a 14-test run succeeded before the final neutral-color increment; they are not substituted for final-source validation.

The neutral-surface source at `819509ce035e1b07829529d4e36ded393776081b` completed **15/15**: all 11 committed shell tests plus four local-only rendering/capture fixture methods. Each unique test emitted status 0 and the runner ended with `OK (15 tests)` and terminal -1. The final change at `d61be4b50c3f4877022008e5493ade1ba78a96ad` only gives the attachment guidance Text an explicit secondary content color; a targeted local-menu rendering test completed **1/1**, and full project compilation/lint was rerun with exit 0. The earlier 15 results are not relabeled as a rerun of that final line. The 11 committed shell test/component inputs are unchanged by that line.

Terminal instrumentation logs, source hashes, actual compile invocation/output, behavioral REDs, unsupported-Dialog probe and offline outputs are in `evidence/`. No screenshots, prior private audit, APK, model bytes, account data or attachment identifiers are included. Tests run exact copied source files on the task-owned API26 x86_64 software emulator, with source hashes checked. Fixtures contain local/synthetic preview state and no ProductClient, account, real provider, transcript, fee or receipt. Their APK is a separate component fixture, not the product APK.

## Scope and remaining work

Production callers in ChatScreen and the existing shell are connected in source and compile. Full product runtime/visual acceptance is pending: this slice does not rebuild or relabel the earlier product APK. Screenshots are private deliverables and are not stored in this repository/report.

This is one approved UI slice, not completion of every page. Search/new-session/settings-footer UI callback migration remains a later slice; plugin pages and Bot/group proposals need their own owners/review. Attachment/document and card capabilities still require genuine host facts and authorized bridges. No new public protocol, fake success, unverified action, Reader Core work, real request, deployment or merge is included. Parent/Leader B owns PR organization and develop integration.
