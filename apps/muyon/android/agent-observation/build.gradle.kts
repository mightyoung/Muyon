import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins { id("org.jetbrains.kotlin.jvm") }
kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
    sourceSets.main {
        // Reuse the single existing private protocol/state implementation unchanged.
        // Extraction is a separate checker migration; never copy its authority/validation here.
        kotlin.srcDir(projectDir.resolve("../../../../experiments/redesign/android-compose-lab/state/src/main/kotlin"))
        kotlin.include("com/mightyoung/muyon/agent/**", "**/AgentServiceContract.kt", "**/AgentServiceClientState.kt", "**/AgentServiceWire.kt")
    }
}
val checkObservation by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("com.mightyoung.muyon.agent.ReceiptObserverChecksKt")
}
tasks.named<Test>("test") { enabled = false }
tasks.named("check") { dependsOn(checkObservation) }
