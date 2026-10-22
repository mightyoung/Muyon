package muyon.bridgechecks

import com.mightyoung.muyon.androidlab.agentipc.main as projectionChecks
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest

/** Actual default native handshake, then the fixed pure metadata fixture main. */
object MapperProbe {
    @JvmStatic fun main(args: Array<String>) {
        check(args.size == 2)
        val source = args[0]
        check(source.matches(Regex("[0-9a-f]{40}")))
        val library = Path.of(args[1]).toRealPath()
        System.setProperty("uniffi.component.muyon_android_contract_bridge.libraryOverride", library.toString())
        check(System.getProperty("os.name") == "Linux")
        BridgeProbe.verifyInfo(source)
        check(Files.readString(Path.of("/proc/self/maps")).contains(library.toString()))
        val hash = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(library))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        println("AGENT_MAPPER_JVM_MAPPED source=$source sha256=$hash")
        projectionChecks()
    }
}
