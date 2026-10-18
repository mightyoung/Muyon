plugins { id("com.android.library"); kotlin("android") }
android {
    namespace = "com.mightyoung.muyon.ocr"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    sourceSets["main"].java.srcDirs("../../kotlin/src/main/kotlin", "../../android/src/main/kotlin", "../../vendor/paddleocr")
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("verified-assets"))
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
val modelRoot = providers.gradleProperty("ocrAssets").orElse(providers.environmentVariable("OCR_ASSETS"))
val verifyAssets by tasks.registering(Exec::class) {
    workingDir(project.projectDir)
    commandLine("python3", "../../checks/asset_cache.py", modelRoot.getOrElse("/missing-ocr-assets"))
}
val stageAssets by tasks.registering(Copy::class) {
    dependsOn(verifyAssets)
    from(modelRoot.map { "$it/PP-OCRv6_tiny_det_onnx" }) { include("inference.onnx"); into("tiny/det") }
    from(modelRoot.map { "$it/PP-OCRv6_tiny_rec_onnx" }) { include("inference.onnx", "inference.yml"); into("tiny/rec") }
    into(layout.buildDirectory.dir("verified-assets/ocr-v6"))
}
tasks.named("preBuild") { dependsOn(stageAssets) }
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.21.1")
    implementation("org.opencv:opencv:4.12.0")
}
dependencyLocking { lockAllConfigurations() }
