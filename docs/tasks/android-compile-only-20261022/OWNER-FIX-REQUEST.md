# Actual Android API compile blocker

Currentfixedproductsource16945df54fd0233a89a41262952e0967d2d0cb59 (CI-onlycommit
 a62c88ce2b46d4d3a7a1f78477f08384a671a84d haszeroproductsourcechanges).
Actual API36/AGP8.11.1/Kotlin2.2.20 JDK17 Gradle8.13 compiler error:

apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/shell/RequestCandidates.kt:24:49
Unresolved reference 'similar'.

The .similar call compares candidate.observation and request_snapshot.observation
inside decodeRequestCandidate. Bothonline andsamecacheoffline actualAndroidcompile
failed atsamecall, notplugin/Gradledownload/Maven-cachefailure. DesktoppureKotlin
runnerexplicitlyusesorg.json JVMjar; classconstantandearlieractualcompileconfirm
thatdesktopAPI contains similar. ThatJVMpassnevercoveredAndroidSDKJSONAPIshape.
LocaljavapoptionaldiagnosticNOT_RUN (binaryabsent); actualAndroidcompilererror is
primaryevidence, no fabricatedAndroidstub orhandwrittenSDK substituted.

Shellowner must provide Android-compatible structural observation equality while
preserving duplicate-observation tamper refusal, missing/NULL/type/array/nesting
and existing schema semantics. Confirm object ordering/numeric equality deliberately;
do not silently substitute serialized-string equality or weaker selected-field check.
RequestCandidateChecks currentlycovers changedstatus; Android-compatible API compile
must be verified through this realcompile-onlyCI. No authority/grant/price/Unknown
or comparison-policy expansion requested. Integrator didnot concurrentlyrewrite
sourceowner businesscomparison. Fixedsourcefollowup needed beforetesttargets.

Parent can return fixedownedminimaldelta; continue sameisolatedCIbranch, rerun actual
newSHA withsamegraphguard. PreviousREDlogs/sourceSHAretain; no status/model/nativegate
skip, no AST/JSON fakes-as-productbuild. AndroidTest/unitcompiles remainNOT_RUN due
maincompiledependencyfailure. No platform/Githubpermissiondenial occurred.
