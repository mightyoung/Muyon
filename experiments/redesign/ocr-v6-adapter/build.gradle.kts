plugins { kotlin("jvm") version "2.1.0" }
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
sourceSets {
    main { kotlin.srcDir("kotlin/src/main/kotlin") }
    test { kotlin.srcDir("kotlin/src/test/kotlin") }
}
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.openpnp:opencv:4.9.0-0")
    testImplementation("net.bytebuddy:byte-buddy:1.15.11")
    testImplementation("net.bytebuddy:byte-buddy-agent:1.15.11")
}
tasks.test { testLogging { events("passed", "failed", "skipped"); showStandardStreams = true } }
// Compile the isolated Android adapter and unchanged SDK sources on the JVM.
// This checks signatures only: it does not build an AAR/APK or execute ART/native code.
val nativeCompile by configurations.creating
val unpackNative by tasks.registering {
    inputs.files(nativeCompile)
    outputs.dir(layout.buildDirectory.dir("native-compile"))
    doLast {
        nativeCompile.files.forEach { file ->
            copy {
                from(zipTree(file)) { include("classes.jar"); rename("classes.jar", file.nameWithoutExtension + "-classes.jar") }
                into(layout.buildDirectory.dir("native-compile"))
            }
        }
    }
}
sourceSets.main { kotlin.srcDirs("android/src/main/kotlin", "vendor/paddleocr") }
dependencies {
    nativeCompile("com.microsoft.onnxruntime:onnxruntime-android:1.21.1@aar")
    nativeCompile("org.opencv:opencv:4.12.0@aar")
    compileOnly(files(unpackNative.map { layout.buildDirectory.dir("native-compile").get().asFileTree.matching { include("*.jar") } }))
    compileOnly("com.google.android:android:4.1.1.4")
    testImplementation("com.google.android:android:4.1.1.4")
}
tasks.named("compileKotlin") { dependsOn(unpackNative) }
tasks.test {
    // External fixtures are verified by models.lock.json before native inference checks.
    systemProperty("ocr.assets", providers.gradleProperty("ocrAssets").orElse("").get())
}
dependencies { implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0") }
dependencyLocking { lockAllConfigurations() }
