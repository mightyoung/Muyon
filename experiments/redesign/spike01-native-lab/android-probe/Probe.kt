package spike01.runner
import uniffi.spike01_bridge_lab.*
import java.security.MessageDigest
import kotlin.concurrent.thread

object Probe {
 @JvmStatic fun main(args: Array<String>) {
  if (args.isNotEmpty()) {
   System.setProperty("jna.library.path", args[0])
   System.setProperty("jna.boot.library.path", args[0])
  }
  println("PLATFORM os=${System.getProperty("os.name")} arch=${System.getProperty("os.arch")} vm=${System.getProperty("java.vm.name")}")
  println("NATIVE_LOAD unicode=${unicodeTableVersion()}")
  fun q(s:String):String = "\"" + s.flatMap { c -> when(c) {
   '"' -> "\\\"".toList(); '\\' -> "\\\\".toList(); '\n' -> "\\n".toList(); '\r' -> "\\r".toList(); '\t' -> "\\t".toList()
   else -> if(c.code<32) "\\u%04x".format(c.code).toList() else listOf(c)
  }}.joinToString("") + "\""
  fun request(s:String, rev:ULong=7uL) = LabRequest(1u, s.map { it.code.toUShort() }, rev, "spike01.name", LabNormalization.NFC, null)
  fun json(r:LabRequest):ByteArray = "{\"protocol\":${r.protocol},\"raw_utf16\":[${r.rawUtf16.joinToString(",")}],\"revision\":${r.revision},\"purpose\":${q(r.purpose)},\"normalization\":\"nfc\",\"note\":null}".toByteArray(Charsets.UTF_8)
  var pairs=0
  for (s in listOf(" A\u030a公司 ", "é", "e\u0301", "\uFEFF名字\uFEFF", "𠀀".repeat(200), "\u180e名字\u180e", "名字\t内部")) {
   for (rev in listOf(0uL,9007199254740993uL,ULong.MAX_VALUE)) {
    val r=request(s,rev); val t=evaluateTyped(r); val j=evaluateJson(json(r))
    val expected="{\"normalized_name\":${q(t.normalizedName)},\"revision\":${t.revision},\"purpose\":${q(t.purpose)},\"note\":null,\"canonical_bytes\":[${t.canonicalBytes.joinToString(",") { (it.toInt() and 255).toString() }}],\"digest\":${q(t.digest)}}"
    check(j.contentEquals(expected.toByteArray(Charsets.UTF_8)))
    check(MessageDigest.getInstance("SHA-256").digest(t.canonicalBytes).joinToString("") { "%02x".format(it.toInt() and 255) }==t.digest)
    pairs++
   }
  }
  fun error(f:()->Unit):String { try { f() } catch(e:LabException) { return e.javaClass.simpleName+":"+e.message }; error("expected domain error") }
  for (r in listOf(request("\uD800"),request("\u0000名字"),request(" "),request("𠀀".repeat(201)),request("名字").copy(protocol=2u),request("名字").copy(purpose="arbitrary"))) {
   check(error { evaluateTyped(r) }==error { evaluateJson(json(r)) })
  }
  error { evaluateJson("{\"capability\":\"synthetic\"}".toByteArray()) }
  val baseline=liveSessionCount(); val session=LabSession(); var callbacks=0
  session.setObserver(object:LabObserver { override fun onReply(digest:String) { callbacks++; check(digest.length==64) } })
  session.run(request("名字")); check(callbacks==1)
  session.unsubscribe(); session.run(request("名字")); check(callbacks==1)
  session.setObserver(object:LabObserver { override fun onReply(digest:String) { throw LabCallbackException.Rejected("synthetic") } })
  check(error { session.run(request("名字")) }.contains("CallbackRejected"))
  session.setObserver(object:LabObserver { override fun onReply(digest:String) { check(error { session.closeSession() }.contains("ReentrantClose")) } })
  session.run(request("名字")); session.closeSession()
  check(error { session.run(request("名字")) }.contains("Closed"))
  session.close(); check(liveSessionCount()==baseline)
  val entered=java.util.concurrent.CountDownLatch(1); val release=java.util.concurrent.CountDownLatch(1)
  val done=java.util.concurrent.CountDownLatch(1); val failures=java.util.concurrent.ConcurrentLinkedQueue<Throwable>()
  val blocking=LabSession()
  blocking.setObserver(object:LabObserver { override fun onReply(digest:String) { entered.countDown(); check(release.await(5,java.util.concurrent.TimeUnit.SECONDS)) } })
  val worker=thread { try { blocking.run(request("名字")) } catch(t:Throwable) { failures.add(t) } }
  check(entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
  val closer=thread { try { blocking.closeSession(); done.countDown() } catch(t:Throwable) { failures.add(t) } }
  val deadline=System.nanoTime()+5_000_000_000L
  while(!blocking.isClosed() && System.nanoTime()<deadline) Thread.yield()
  val marked=blocking.isClosed(); val early=done.count==0L; release.countDown()
  worker.join(5000); closer.join(5000)
  check(marked && !early && done.count==0L && !worker.isAlive && !closer.isAlive && failures.isEmpty())
  blocking.close(); check(liveSessionCount()==baseline)
  var caught=false
  try { syntheticPanic() } catch(e:InternalException) { caught=true }
  check(caught); check(evaluateTyped(request("名字")).normalizedName=="名字")
  val r=request(" A\u030a公司 ")
  val n=1000
  val typedStart=System.nanoTime(); repeat(n) { evaluateTyped(r) }; val typedNs=(System.nanoTime()-typedStart)/n
  val raw=json(r); val jsonStart=System.nanoTime(); repeat(n) { evaluateJson(raw) }; val jsonNs=(System.nanoTime()-jsonStart)/n
  println("PASS pairs=$pairs errors callbacks unsubscribe close_wait reentry native_drop panic")
  println("BENCH exploratory iterations=$n typed_ns=$typedNs json_ns=$jsonNs no_SLA_selection")
 }
}
