# Preserved first failure — no runtime acceptance

- Run39140979633 attempt1 completed FAILURE, source `489178b0c5c80979156ad4ee0b2eba8955465191`.
- scoped genuine binding build/reproduction PASS; arm64-v8a and x86_64 native API26 producers PASS.
- All seven package-device jobs failed Gradle Kotlin DSL at app/build.gradle.kts:51:22 `initWith(getByName("debug"))`, unresolved receiver. Each instrumentation step SKIPPED, so actual Android acceptance **NOT_RUN** for every scenario. No runtime success is claimed.
- Independent source audit separately found startup/destroy queued retirement rejection not covered by these seven cases. This run is retained unchanged and is not rerun or cancelled.
- Evidence: direct GitHub run/jobs API metadata plus bounded failed-job diagnostic excerpt. No artifact archive retrieval was attempted. Prior forbidden403 archive was untouched.
- Follow-up must qualify build type lookup, add minimal eighth actual constructor/destroy barrier, and repair executor lifetime/dispatch. New source needs independent review and a distinct CI run.
