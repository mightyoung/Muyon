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
    androidResources { noCompress += listOf("gguf", "onnx") }
    providers.gradleProperty("muyonModelAssets").orNull?.let {
        require(File(it).isAbsolute) { "Model asset directory must be absolute" }
        sourceSets.getByName("main").assets.srcDir(it)
    }
    sourceSets.getByName("androidTest").assets.srcDir(rootProject.file("../../docs/contracts/muyon-android/fixtures"))
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
val verifyModelAssets by tasks.registering {
    doLast {
        val directory = File(providers.gradleProperty("muyonModelAssets").orNull
            ?: error("Prepare fixed offline assets and set muyonModelAssets"), "local-models")
        val fixed = mapOf(
            "embedding.gguf" to "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135",
            "det.onnx" to "a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d",
            "rec.onnx" to "da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092",
            "dictionary.json" to "d858428fbe0ada92b439a5f277b51bc1b318fd985d80946a3ce859d7f2446a92"
        )
        fixed.forEach { (name, expected) ->
            val hash = MessageDigest.getInstance("SHA-256")
            directory.resolve(name).inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
            }
            require(hash.digest().joinToString("") { "%02x".format(it) } == expected) { "Fixed model mismatch: $name" }
        }
    }
}
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
        require(expected.keys == listOf("arm64-v8a", "x86_64").flatMap { abi ->
            listOf("$abi/libmuyon_android_product.so", "$abi/libmuyon_local_embedding.so")
        }.toSet()) { "Native manifest set mismatch" }
        for (path in expected.keys) {
            val library = directory.resolve(path)
            val digest = MessageDigest.getInstance("SHA-256").digest(library.readBytes()).joinToString("") { "%02x".format(it) }
            require(expected[path] == digest) { "Native input hash mismatch: $path" }
        }
    }
}
tasks.configureEach {
    if (name == "mergeDebugNativeLibs" || name == "mergeReleaseNativeLibs") dependsOn(verifyProductNativeInputs)
    if (name == "mergeDebugAssets" || name == "mergeReleaseAssets") dependsOn(verifyModelAssets)
}
dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.23.0")
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
