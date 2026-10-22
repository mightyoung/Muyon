pluginManagement {
    repositories { mavenCentral(); gradlePluginPortal() }
    plugins { id("org.jetbrains.kotlin.jvm") version "2.2.20" }
}
dependencyResolutionManagement { repositories { mavenCentral() } }
rootProject.name = "receipt-observation-verification"
include(":agent-observation")
project(":agent-observation").projectDir = file("/workspace/leaderb-a/apps/muyon/android/agent-observation")
