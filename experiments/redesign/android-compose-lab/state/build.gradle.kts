import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins { id("org.jetbrains.kotlin.jvm") }
kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }
val checkState by tasks.registering(JavaExec::class) {
    dependsOn(tasks.testClasses)
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("com.mightyoung.muyon.androidlab.StateChecksKt")
}
tasks.named<Test>("test") {
    enabled = false
    description = "No JUnit suite: the complete stdlib checks run through checkState."
}
tasks.named("check") { dependsOn(checkState) }
