plugins { id("com.android.application") }
android {
    namespace = "com.mightyoung.muyon.ocr.packaging"
    compileSdk = 36
    defaultConfig { applicationId = "com.mightyoung.muyon.ocr.packaging"; minSdk = 26; targetSdk = 36; versionCode = 1; versionName = "1" }
    signingConfigs.getByName("debug") { storeFile = layout.buildDirectory.file("ocr-probe-debug.keystore").get().asFile }
    packaging { jniLibs { useLegacyPackaging = false; keepDebugSymbols += "**/*.so" } }
}
dependencies { implementation(project(":adapter")) }
dependencyLocking { lockAllConfigurations() }
