package muyon.rd.p05c

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.file.Path
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@Suppress("UNCHECKED_CAST")
fun Any?.objectValue(): Map<String,Any?> = this as? Map<String,Any?> ?: error("Expected JSON object")
fun Map<String,Any?>.text(key:String):String = this[key] as? String ?: error("Expected string field $key")
fun decimal(value:Any?):String {
    val text=value as? String ?: error("Counter must be string")
    require(Regex("0|[1-9][0-9]*").matches(text) && text.toULongOrNull()!=null){"Invalid decimal u64"}
    return text
}
data class Domain(val store:String,val scope:String,val stream:String) {
    fun wire():Map<String,Any?> = mapOf("store" to store,"scope" to scope,"stream" to stream)
    companion object {fun from(value:Any?):Domain {val m=value.objectValue();require(m.keys==setOf("store","scope","stream"));return Domain(m.text("store"),m.text("scope"),m.text("stream"))}}
}
data class Reply(val wire:Map<String,Any?>) {
    val kind get()=wire.text("kind")
    val domain get()=Domain.from(wire["domain"])
    val epoch get()=wire.text("display_epoch")
    val admission get()=wire.text("display_admission")
    val snapshot get()=wire["snapshot"]?.objectValue()
    val plan get()=wire["plan"]?.objectValue()
    val receipt get()=wire["receipt"]?.objectValue()
    companion object {
        fun parse(text:String,requestId:String):Reply {
            val w=Json.parse(text).objectValue()
            require(w.keys==setOf("protocol","request_id","kind","reason","domain","display_epoch","display_admission","snapshot","plan","receipt")){"Reply fields"}
            val invalidRequest=w["kind"]=="rejected" && w["reason"]=="invalid_request" && w["request_id"]=="" && w["display_epoch"]==""
                &&w["snapshot"]==null && w["plan"]==null && w["receipt"]==null
            require(w["protocol"]==JsonNumber("0") && (w["request_id"]==requestId || invalidRequest)){"Reply correlation"}
            require(w["kind"] in setOf("hello","snapshot","prepared","committed","conflict","rejected","unknown"))
            require(w["reason"]==null || w["reason"] is String)
            require(w["display_epoch"] is String && w["display_admission"] in setOf("current","stale"))
            Domain.from(w["domain"])
            w["snapshot"]?.objectValue()?.let {s->
                require(s.keys==setOf("cursor","suppliers"));val cursor=s["cursor"].objectValue()
                require(cursor.keys==setOf("store","scope","stream","seq"));decimal(cursor["seq"])
                Domain.from(cursor.filterKeys {it!="seq"})
                val suppliers=s["suppliers"] as? List<*> ?: error("Supplier array")
                require(suppliers.size<=1000)
                suppliers.forEach {row->val m=row.objectValue();require(m.keys==setOf("id","name","revision"));m.text("id");m.text("name");decimal(m["revision"])}
            }
            w["plan"]?.objectValue()?.let {p->
                require(p.keys==setOf("id","intent","object_id","expected_revision","normalized_name","parameters_digest"))
                listOf("id","intent","object_id","normalized_name","parameters_digest").forEach {p.text(it)};decimal(p["expected_revision"])
            }
            w["receipt"]?.objectValue()?.let {r->
                require(r.keys==setOf("kind","id","intent","object_id","expected_revision","result_revision","normalized_name","parameters_digest","commit_cursor"))
                require(r["kind"]=="synthetic");listOf("id","intent","object_id","normalized_name","parameters_digest").forEach {r.text(it)}
                decimal(r["expected_revision"]);decimal(r["result_revision"])
                val cursor=r["commit_cursor"].objectValue();require(cursor.keys==setOf("store","scope","stream","seq"));decimal(cursor["seq"]);Domain.from(cursor.filterKeys {it!="seq"})
            }
            when(w["kind"]) {
                "committed"->require(w["receipt"]!=null){"Committed requires receipt"}
                "unknown","rejected","conflict"->require(w["receipt"]==null){"Non-effect cannot carry receipt"}
                "prepared"->require(w["plan"]!=null && w["receipt"]==null){"Prepared is not an effect"}
                "hello","snapshot"->require(w["snapshot"]!=null && w["receipt"]==null){"Read requires snapshot, no effect"}
            }
            return Reply(w)
        }
    }
}
class TransportUnavailable(val code:String):Exception(code)
enum class LabSeed(val file:String) { NORMAL("seed.json"), LOST_REPLY("seed-lost-reply.json") }
/** Fixed trusted local executable, no shell and no renderer-callable process/path API. */
class CorePort private constructor(private val process:Process):AutoCloseable {
    private val reader=Executors.newSingleThreadExecutor {r->Thread(r,"rd-p05-jvm-frame").apply {isDaemon=true}}
    private var nextId=0L
    private var closed=false
    @Synchronized
    fun request(op:String,domain:Domain,epoch:String,business:Map<String,Any?> = emptyMap()):Reply {
        if(closed) throw TransportUnavailable("CLOSED")
        val id="jvm-${++nextId}"
        val request=linkedMapOf<String,Any?>("protocol" to 0,"request_id" to id,"op" to op,"domain" to domain.wire(),"display_epoch" to epoch)
        require(business.keys.none {it in request.keys}){"Transport meta overwrite"};request.putAll(business)
        return sendFrame(request)
    }
    /** Trusted CLI-only frame sender allows negative protocol fixtures; Rust decides rejection. */
    @Synchronized
    fun sendFrame(request:Map<String,Any?>):Reply {
        if(closed) throw TransportUnavailable("CLOSED")
        val id=request["request_id"] as? String ?: ""
        val bytes=(Json.stringify(request)+"\n").toByteArray(Charsets.UTF_8)
        require(bytes.size<=32769){"Frame limit"}
        try {
            process.outputStream.write(bytes);process.outputStream.flush()
            val frame=reader.submit<String> {readFrame()}.get(5,TimeUnit.SECONDS)
            return Reply.parse(frame,id)
        } catch(e:Exception) {close();throw TransportUnavailable(if(e is TransportUnavailable) e.code else "TRANSPORT_OR_REPLY_INVALID")}
    }
    private fun readFrame():String {
        val out=ByteArrayOutputStream()
        while(true){val b=process.inputStream.read();if(b<0) throw TransportUnavailable("EOF");if(b==10) break;if(out.size()>=32768) throw TransportUnavailable("FRAME_LIMIT");out.write(b)}
        return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(out.toByteArray())).toString()
    }
    override fun close() {if(closed)return;closed=true;process.destroyForcibly();reader.shutdownNow();process.waitFor(2,TimeUnit.SECONDS)}
    companion object {
        const val BINARY="/tmp/rd-p05-core-target/debug/rd-p05-core"
        fun open(seed:LabSeed,fixtures:Path,stderr:Path):CorePort {
            val owned=fixtures.resolve(seed.file).toRealPath()
            require(owned.parent==fixtures.toRealPath()){"Seed escape"}
            val builder=ProcessBuilder(BINARY,"--seed",owned.toString())
            builder.redirectError(stderr.toFile())
            return CorePort(builder.start())
        }
    }
}
/** Business command retains raw code units. Only Rust validates/normalizes/CAS/deduplicates. */
data class Business(val objectId:String,val intent:String,val expectedRevision:String,val raw:String) {
    fun fields(planId:String?=null):Map<String,Any?> {
        decimal(expectedRevision)
        val m=linkedMapOf<String,Any?>("object_id" to objectId,"intent" to intent,"expected_revision" to expectedRevision,"raw_utf16" to raw.map {it.code})
        if(planId!=null)m["plan_id"]=planId
        return m
    }
}

/** Trusted harness diagnostics always stay in its independently owned output directory. */
fun ownedEvidence(name:String):Path {
    require(name.matches(Regex("[a-zA-Z0-9._-]+")))
    val root=Path.of(System.getenv("RD_P05_EVIDENCE_DIR") ?: System.getenv("RD_P05_OUTPUT") ?: "/tmp/rd-p05-jvm-output").toAbsolutePath().normalize()
    require(root.startsWith(Path.of("/tmp")) || root.startsWith(Path.of("/workspace/reports"))){"External evidence directory required"}
    java.nio.file.Files.createDirectories(root)
    return root.resolve(name)
}
