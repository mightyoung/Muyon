package com.mightyoung.muyon.androidlab
/** Actual generated Android source on JVM, unavailable paths only; not Android/native-success evidence. */
fun main() {
    val cases = linkedMapOf<String, () -> Unit>(
        "ordinary no-native input is unavailable" to { check(runCatching { GeneratedDiagnosticPort(1u, "").bridgeInfo() }.exceptionOrNull().let { it is DiagnosticNativeFailure && it.code == DiagnosticError.NATIVE_LOAD }) },
        "invalid expected protocol is closed" to { check(runCatching { GeneratedDiagnosticPort(2u, "a".repeat(40)).bridgeInfo() }.exceptionOrNull().let { it is DiagnosticNativeFailure && it.code == DiagnosticError.PROTOCOL_MISMATCH }) },
        "actual missing generated native library is safe" to { check(runCatching { GeneratedDiagnosticPort(1u, "a".repeat(40)).bridgeInfo() }.exceptionOrNull().let { it is DiagnosticNativeFailure && it.code == DiagnosticError.NATIVE_LOAD }) },
        "repeat after class initialization failure is safe" to { check(runCatching { GeneratedDiagnosticPort(1u, "a".repeat(40)).bridgeInfo() }.exceptionOrNull().let { it is DiagnosticNativeFailure && it.code == DiagnosticError.NATIVE_LOAD }) },
    )
    var failures = 0
    cases.forEach { (name, test) -> try { test(); println("PASS actual adapter $name") } catch (error: Throwable) { failures++; println("FAIL actual adapter $name: ${error.javaClass.simpleName}") } }
    check(failures == 0) { "$failures/${cases.size} actual adapter boundary checks failed" }
    println("4/4 actual generated adapter unavailable-boundary checks passed; Android/native success NOT_RUN")
}
