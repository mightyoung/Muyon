import java.security.MessageDigest
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
plugins { id("com.android.application"); id("org.jetbrains.kotlin.android"); id("org.jetbrains.kotlin.plugin.compose") }
android {
    namespace = "com.mightyoung.muyon.study"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    defaultConfig { applicationId = "com.mightyoung.muyon.study"; minSdk = 26; targetSdk = 36; versionCode = 2; versionName = "1.0.1"; ndk { abiFilters += listOf("arm64-v8a", "x86_64") }; testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
    buildFeatures { compose = true; buildConfig = true }
    androidResources { noCompress += "zip" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    packaging { resources.excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1") }
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.09.01"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("net.java.dev.jna:jna:5.19.1@aar")
    implementation("com.google.android.gms:play-services-auth:21.4.0")
    implementation("com.alphacephei:vosk-android:0.3.75@aar")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.09.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
val verifyStudyInputs by tasks.registering {
    doLast {
        val model=file("src/main/assets/model.zip")
        require(model.isFile) { "Run prepare-inputs.py to bundle the offline Chinese model" }
        val hash=MessageDigest.getInstance("SHA-256").digest(model.readBytes()).joinToString(""){"%02x".format(it)}
        require(hash=="3af8b0e7e0f835ae9d414ce5df580237a3cfb08d586c9fbbb0f7ff29ad5b14ba") { "Offline model checksum mismatch" }
        listOf("arm64-v8a","x86_64").forEach { require(file("src/main/jniLibs/$it/libmuyon_study.so").isFile) { "Missing Rust $it library; run build-native.sh" } }
    }
}
tasks.configureEach { if(name=="mergeDebugAssets"||name=="mergeReleaseAssets"||name=="mergeDebugNativeLibs"||name=="mergeReleaseNativeLibs") dependsOn(verifyStudyInputs) }
