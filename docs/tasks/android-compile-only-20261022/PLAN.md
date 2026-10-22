# Exact-source Android compiler-only CI plan

Base16945df54fd0233a89a41262952e0967d2d0cb59; oneisolatedbranch
lab/android-compile-20261022. No productsource/buildscript/AGP/native/model changes.
Repositorypublicconfirmed via currentauthorizedghread private=false. Standard
ubuntu-24.04 job additionally requires eventrepository.private=false; no paidrunner,
secretsinputs/artifactupload/persistentcache/deploy/PR/main/develop changes.

Only pushtrigger exactbranch with narrowworkflow/driver/app paths. Existingpush
workflows inspected: no automaticFlutter/product/oldlab/I04 suite matches thisbranch.
Defaultbranchmain has onlyverify dispatch; no workflow_dispatch assumption.
Checkout fixedgithub.sha withpersistcredentialsfalse, assertgitHEAD==eventSHA.
Pinned existingcheckout11bd719/setupjava c5195ef (Temurin17); Gradle8.13 download
fromofficialservices.gradle.org with existingSHA25620f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78.
Runnerofficialsdkmanager installs ONLYplatformandroid36/buildtools35, noNDK/CMake/
model/assets/nativecompilation/emulator/engine. GRADLE_USER_HOME inephemeralRUNNER_TEMP,
no cacheaction/upload or credentialsetting. No localSDK install/denialworkaround.

Per target in order: compileDebugKotlin, compileDebugAndroidTestKotlin,
compileDebugUnitTestKotlin. Run actualGradle --dry-run withpre-actiongraph listener.
Exact taskpaths printed ordinarylogs and checked againstexplicitpositivecompiler/
resourceprerequisite list. packageDebugResources/processDebugManifestForPackage
are specificallyallowed intermediate tasks, not APK packaging. Anyunknownor
verifyModelAssets/verifyProductNativeInputs/mergeDebugAssets/mergeDebugNativeLibs/
packageDebug/assemble/install/connected/test/custom runtime task stops route.
No -x/skipguard/fakeinputs. No customGradletask isadded: listener onlyrecords/
validatesthe existinggraph BEFORE actions. Actualexecutiongraph must matchdryrun
list exactly; writes separategraphfile beforecomparison, neveroverwriteswitness.

Only safegraph proceeds onlineGradlecompile toresolve actualGoogle/Maven dependencies,
then --offline --rerun-tasks with SAME jobcache. No clean or emptycacheofflineretry.
On onlineconfiguration/dependency failure, offlineNOT_RUN. Ifactualcompilerphase
startsandfailswithsourceerrorsafterresolution, samecacheofflinefailurecanbecaptured;
never turn eitherfailuretopass. Anyfailedtarget stopslaterdependenttargets, statuses
remainNOT_RUN. No app/unit/instrumentation tests run; only compiler tasks requested.

Driverpolicy3localunittests + PythonAST/YAMLparse run beforeindependentreview.
These are safetygate tests, NOT Androidcompile. Fixedworkflow+taskgraphplan must
be independently reviewed BEFORE branchpush/CItrigger. Actualgraph reviewed by
failclosed policyinjobandreadbacklogs; no localGradle/SDK available toclaimdryrun.
Monitor actualCI toterminal; preserveexactSHA/commands/graphs/exit/NOT_RUN andnormal
joblogs. NewGithubpermissionrefusal means stop, no alternatecredentials/APIroute.
No forbiddenold403logsretrieval. Noartifactdownloadneeded; ordinarylogs only.

Compilationonlysyntax/types: notAPK/package/device/lifecycle/PFD/longreading/renderer/
Hostprincipal/reauth/Officequalification. Existingpublication/verified/claimsendHOLD.
Unrelatedc0Fluttercoverage2395<2401 isnotAndroidfailure; no gatebaseline lowered.
