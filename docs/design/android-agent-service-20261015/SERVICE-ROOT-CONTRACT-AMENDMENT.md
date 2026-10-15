# Service private-root clarification

Status: fixed design amendment, independent review pending; implementation and Android runtime acceptance NOT_RUN.

## Problem and decision

AOSP ContextImpl.getFilesDir delegates directory creation to ensurePrivateDirExists, whose default mode is0771. Source: [AOSP ContextImpl](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/app/ContextImpl.java), inspected source blob dcbdc2348fbc244e9b84dbc39a24c3838552137d. This establishes that canonical filesDir is not guaranteed0700; it is not a measurement of a selected device. Passing filesDir directly to the existing strict0700 Rust constructor can fail InvalidRoot. Repeating the Rust namespace in Kotlin also gives an unintended double namespace.

The Service-owned background bootstrap uses `canonical filesDir/agent-service-root` as the dedicated0700 parent. Its canonical absolute path is config.private_root. Rust alone creates and owns `private_root/native-agent-service-v1` and its lock/index/run evidence. The outer parent name deliberately differs from the Rust namespace. This narrows the existing private storage layout without introducing a new service, permission, broker, daemon, model, device or resource allocation.

## Bootstrap requirements

- Derive filesDir solely from the Service Context, never Binder/UI input. All preparation is on the existing Service bootstrap executor, outside main/Binder/control locks.
- Resolve the trusted Context filesDir. The expected dedicated child must be a direct child of that canonical parent.
- If the child is absent, create it once with mode0700. On an existing entry or creation race, inspect the entry without following a final symlink. Reject symlink, non-directory, wrong owner UID, or any mode other than0700. Verify the freshly created entry by the same rules.
- Canonicalize the accepted child and require equality with the expected direct child path/containment. Rust independently retains its canonical-path, ancestor-symlink, UID and strict0700 checks.
- Do not chmod filesDir, silently chmod/repair an existing child, replace/delete entries, clear persisted evidence or retry unsafe initialization. A preparation error leaves the local transport unavailable; do not invent a Rust epoch, Ready or business result.
- No UI process opens/creates this storage or constructs an Agent. Same UID still permits trusted app components to access files; this remains address-space/fault isolation rather than a hostile same-UID sandbox.

## Ownership and validation

The UI owner changes only background root preparation and its own task document after design review. Native root validation, namespace, quotas and receipts remain strict and unchanged. The checker records the final source/layout when exercising actual default generated JVM controller and final Android build. Ordinary AIDL/Kotlin/lint builds prove compilation/static API compatibility only; actual Android mode/UID/SELinux/fsync/lock/process behavior remains NOT_RUN without separately authorized platform execution. Existing immutable CI reports retain their original source and earlier layout limitations.
