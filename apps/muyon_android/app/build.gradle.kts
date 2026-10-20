import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.File
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.mightyoung.muyon.product"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    defaultConfig {
        applicationId = "com.mightyoung.muyon.product"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "MUYON_SOURCE", "\"${providers.gradleProperty("muyonSource").orNull.orEmpty()}\"")
    }
    buildFeatures { compose = true; buildConfig = true; aidl = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    providers.gradleProperty("muyonProductNativeInputs").orNull?.let {
        require(File(it).isAbsolute) { "Product native input directory must be absolute" }
        sourceSets.getByName("main").jniLibs.srcDir(it)
    }
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
val verifyProductNativeInputs by tasks.registering {
    doLast {
        val input = providers.gradleProperty("muyonProductNativeInputs").orNull
            ?: error("Build product libraries with build-native.sh and set muyonProductNativeInputs")
        val directory = File(input)
        val manifest = directory.parentFile.resolve("SHA256SUMS")
        val buildId = directory.parentFile.resolve("build-id.txt").readText().trim()
        require(buildId == providers.gradleProperty("muyonSource").orNull) { "Product source identity mismatch" }
        val expected = manifest.readLines().associate { line ->
            val fields = line.trim().split(Regex("\\s+"), limit = 2)
            require(fields.size == 2 && fields[0].matches(Regex("[0-9a-f]{64}")))
            fields[1] to fields[0]
        }
        for (abi in listOf("arm64-v8a", "x86_64")) {
            val path = "$abi/libmuyon_android_product.so"
            val library = directory.resolve(path)
            val digest = MessageDigest.getInstance("SHA-256").digest(library.readBytes()).joinToString("") { "%02x".format(it) }
            require(expected[path] == digest) { "Native input hash mismatch: $abi" }
        }
    }
}
tasks.configureEach {
    if (name == "mergeDebugNativeLibs" || name == "mergeReleaseNativeLibs") dependsOn(verifyProductNativeInputs)
}
dependencies {
    implementation("net.java.dev.jna:jna:5.19.1@aar")
    implementation(platform("androidx.compose:compose-bom:2025.09.01"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.09.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
