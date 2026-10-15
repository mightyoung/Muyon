package muyon.bridgechecks

import com.mightyoung.muyon.androidbridge.*
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest

object PanicProbe {
    @JvmStatic fun main(args: Array<String>) {
        check(args.size == 2)
        val source = args[0]
        val library = Path.of(args[1]).toRealPath()
        System.setProperty("uniffi.component.muyon_android_contract_bridge.libraryOverride", library.toString())
        BridgeProbe.verifyInfo(source)
        check(Files.readString(Path.of("/proc/self/maps")).contains(library.toString()))
        val hash = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(library)).joinToString("") { "%02x".format(it.toInt() and 255) }
        println("ANDROID_BRIDGE_PANIC_MAPPED source=$source sha256=$hash")
        var contained = false
        try { ffiTestPanicProbe() } catch (_: BridgeException.InternalFailure) { contained = true }
        check(contained) { "ANDROID_BRIDGE_PANIC_NOT_CONTAINED" }
        val request = BridgeProbe.request(id = "after_panic")
        BridgeProbe.verifyReport(validateBundledContract(request), request, source, "equipment_loan", 1u)
        println("ANDROID_BRIDGE_JVM_PASS panic_is_typed_and_valid_sibling_recovers")
    }
}
