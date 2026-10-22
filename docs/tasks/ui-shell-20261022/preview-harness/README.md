# Isolated runtime component preview scaffold

This directory is tooling for clearly labelled synthetic component previews, not
production application code. Copy this scaffold to a task-owned external directory,
then run materialize_sources.py --repo <Muyon checkout> --out <preview directory>.
It takes byte-identical sources/resources from43's fixed commit and refuses to
replace different existing outputs. Requires the real SDK36/JDK17/Gradle8.13 and
project-pinned official dependencies; no fake Android classes or ProductClient.

Set normal task ANDROID_HOME/ANDROID_USER_HOME/JAVA_HOME/GRADLE_USER_HOME. The archived
local.init.gradle and restore-maven.py are exact task-local recovery tooling examples
with /workspace paths; adapt directory paths deliberately for another task. No proxy
or network-security settings are changed. Build :app:assembleDebug and
:app:assembleDebugAndroidTest only in this preview project. These successes do not
make the full product's native/model package gates pass.

owned_emulator_adb.py and capture.py show the exact raw framebuffer path, with
fixed owned-device port, CNXN-only connection, no AUTH workaround and ANR rejection.
They are bounded task utilities, not production ADB SDK/security implementations.
Preserve caption and source evidence; all UI fixture data are synthetic. Follow
actual normal SDK device authentication if a different device requires it.
