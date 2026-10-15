package muyon.bridgechecks

import com.mightyoung.muyon.androidbridge.*
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest

object BridgeProbe {
    private fun pass(name: String, body: () -> Unit) {
        body()
        println("ANDROID_BRIDGE_JVM_PASS $name")
    }
    fun request(variant: DiagnosticVariant = DiagnosticVariant.EQUIPMENT, id: String = "jvm_request_1") =
        DiagnosticRequest(1u, id, variant)
    fun verifyInfo(source: String) {
        val info = bridgeInfo()
        check(info.protocol == 1u && info.buildIdentity == source) { "ANDROID_BRIDGE_JVM_REACH: actual native protocol/build identity" }
        check(info.capability == DiagnosticCapability.BUNDLED_DECLARATION_VALIDATION)
        check(!info.model && !info.attachments && !info.businessRead && !info.write && !info.execute)
    }
    fun verifyReport(report: DiagnosticReport, request: DiagnosticRequest, source: String, namespace: String, relations: UInt) {
        check(report.protocol == 1u && report.requestId == request.requestId && report.variant == request.variant)
        check(report.buildIdentity == source && report.namespace == namespace)
        check(report.catalogGeneration == 1uL)
        check(report.dataCount == 2u && report.operationCount == 1u && report.relationCount == relations && report.viewCount == 1u)
    }
    @JvmStatic fun main(args: Array<String>) {
        check(args.size == 3) { "probe arguments" }
        val mode = args[0]
        val source = args[1]
        val library = Path.of(args[2]).toAbsolutePath()
        System.setProperty("uniffi.component.muyon_android_contract_bridge.libraryOverride", library.toString())
        if (mode == "load-negative") {
            check(!Files.exists(library))
            var unavailable = false
            try { bridgeInfo() } catch (_: LinkageError) { unavailable = true }
            pass("missing_native_load_stays_unavailable") { check(unavailable) }
            return
        }
        check(System.getProperty("os.name") == "Linux")
        val actual = library.toRealPath()
        val hash = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(actual)).joinToString("") { "%02x".format(it.toInt() and 255) }
        verifyInfo(source)
        check(Files.readString(Path.of("/proc/self/maps")).contains(actual.toString())) { "ANDROID_BRIDGE_JVM_REACH: actual .so mapped" }
        println("ANDROID_BRIDGE_JVM_MAPPED source=$source sha256=$hash")
        if (mode == "jvm-red") {
            val req = request()
            val report = try { validateBundledContract(req) } catch (_: BridgeException.InternalFailure) {
                println("ANDROID_BRIDGE_JVM_STUB_REACHED code=internal_failure")
                null
            }
            check(report != null) { "ANDROID_BRIDGE_JVM_RED: actual Rust bundled declaration must validate" }
            verifyReport(report, req, source, "equipment_loan", 1u)
            println("ANDROID_BRIDGE_JVM_PASS bundled_metadata_positive")
            return
        }
        check(mode == "full")
        pass("native_handshake") { verifyInfo(source) }
        pass("bundled_metadata_positive") {
            val req = request(); verifyReport(validateBundledContract(req), req, source, "equipment_loan", 1u)
        }
        pass("all_variants_repeat_identity_counts") {
            for ((variant, namespace, relations) in listOf(
                Triple(DiagnosticVariant.EQUIPMENT, "equipment_loan", 1u),
                Triple(DiagnosticVariant.RESEARCH, "research", 1u),
                Triple(DiagnosticVariant.INQUIRY, "inquiry", 2u),
                Triple(DiagnosticVariant.SEEDED_EQUIPMENT, "module_f65579dc", 1u))) {
                repeat(2) { round ->
                    val req = request(variant, "repeat_$round")
                    verifyReport(validateBundledContract(req), req, source, namespace, relations)
                }
            }
        }
        pass("protocol_rejection_has_valid_siblings") {
            for (protocol in listOf(0u, 2u, UInt.MAX_VALUE)) {
                var denied = false
                try { validateBundledContract(request().copy(protocol = protocol)) }
                catch (_: BridgeException.UnsupportedProtocol) { denied = true }
                check(denied)
                val req = request(); verifyReport(validateBundledContract(req), req, source, "equipment_loan", 1u)
            }
        }
        pass("request_id_bounds_have_valid_siblings") {
            for (id in listOf("A", "_", "-", "Z9_safe-ID", "a".repeat(64))) {
                val req = request(id = id); verifyReport(validateBundledContract(req), req, source, "equipment_loan", 1u)
            }
            for (id in listOf("", "a".repeat(65), "has.dot", "space id", "line\nbreak", "tab\tid", "null\u0000id", "中文", "é", "🚀")) {
                var denied = false
                try { validateBundledContract(request(id = id)) }
                catch (_: BridgeException.InvalidRequestId) { denied = true }
                check(denied)
                val req = request(); verifyReport(validateBundledContract(req), req, source, "equipment_loan", 1u)
            }
        }
    }
}
