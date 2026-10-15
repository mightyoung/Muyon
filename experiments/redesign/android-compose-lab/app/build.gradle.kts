import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
// Ordinary source builds do not resolve Python, native inputs or any Rust tool.
val bridgeInputs = providers.gradleProperty("muyonBridgeInputs").orNull
val bridgeSourceSha = providers.gradleProperty("muyonBridgeSourceSha").orNull
require((bridgeInputs == null) == (bridgeSourceSha == null)) {
    "muyonBridgeInputs and muyonBridgeSourceSha must be supplied together"
}
val bridgeRoot = bridgeInputs?.let {
    require(it.isNotBlank() && File(it).isAbsolute && File(it).isDirectory) { "Invalid absolute muyonBridgeInputs directory" }
    require(Regex("[0-9a-f]{40}").matches(bridgeSourceSha!!)) { "Invalid independent muyonBridgeSourceSha" }
    File(it)
}
val repositoryRoot = rootProject.projectDir.resolve("../../..").canonicalFile
val verifier = repositoryRoot.resolve("experiments/redesign/android-rust-bridge-lab/checks/verify_inputs.py")
val binding = projectDir.resolve("src/main/kotlin/com/mightyoung/muyon/androidbridge/muyon_android_contract_bridge.kt")
val androidConfig = repositoryRoot.resolve("experiments/redesign/android-rust-bridge-lab/core/uniffi.android.toml")

android {
    namespace = "com.mightyoung.muyon.androidlab"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    defaultConfig {
        applicationId = "com.mightyoung.muyon.androidlab"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.1-lab"
        buildConfigField("int", "MUYON_BRIDGE_PROTOCOL", "1")
        buildConfigField("String", "MUYON_BRIDGE_SOURCE_SHA", "\"${bridgeSourceSha.orEmpty()}\"")
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures { compose = true; buildConfig = true; aidl = true }
    packaging { jniLibs { keepDebugSymbols += setOf("**/libmuyon_android_contract_bridge.so", "**/libjnidispatch.so") } }
    if (bridgeRoot != null) sourceSets.getByName("main").jniLibs.srcDir(bridgeRoot.resolve("jniLibs"))
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
dependencies {
    implementation(project(":state"))
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

if (bridgeRoot != null) {
    val verifyBridgeInputs = tasks.register("verifyBridgeInputs") {
        description = "Strict shared verification of explicit offline bridge packaging inputs"
        inputs.dir(bridgeRoot)
        inputs.file(binding)
        inputs.file(androidConfig)
        inputs.file(verifier)
        inputs.property("expectedSourceSha", bridgeSourceSha!!)
        // Run for every optional packaging build; supplied external staging is not a trusted cache.
        outputs.upToDateWhen { false }
        doLast {
            val jna = configurations.getByName("debugRuntimeClasspath").resolvedConfiguration.resolvedArtifacts.single {
                it.moduleVersion.id.group == "net.java.dev.jna" && it.name == "jna" &&
                    it.moduleVersion.id.version == "5.19.1" && it.extension == "aar"
            }.file
            providers.exec {
                commandLine("python3", verifier.absolutePath,
                    "--input-root", bridgeRoot.absolutePath,
                    "--expected-source-sha", bridgeSourceSha!!,
                    "--binding", binding.absolutePath,
                    "--android-config", androidConfig.absolutePath,
                    "--jna-aar", jna.absolutePath)
            }.standardOutput.asText.get().also { require(it == "BRIDGE_INPUTS_VALID\n") { "Bridge verifier did not confirm inputs" } }
        }
    }
    tasks.named("preBuild") { dependsOn(verifyBridgeInputs) }
}
