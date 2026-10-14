package muyon.rd.p05c

private val domain=Domain("store","scope","stream")
private fun snapshot(seq:String,name:String)=mapOf<String,Any?>("cursor" to (domain.wire()+mapOf("seq" to seq)),"suppliers" to listOf(mapOf("id" to "a","name" to name,"revision" to "8")))
private fun reply(epoch:String,admission:String,snapshot:Map<String,Any?>?=null,receipt:Map<String,Any?>?=null)=Reply(mapOf("domain" to domain.wire(),"display_epoch" to epoch,"display_admission" to admission,"snapshot" to snapshot,"receipt" to receipt,"plan" to null,"kind" to if(receipt==null)"snapshot" else "committed"))
fun main() {
    var passed=0;var failed=0
    fun test(name:String,body:()->Unit){try{body();println("PASS $name");passed++}catch(e:Throwable){println("FAIL $name: ${e.message}");failed++}}
    test("current snapshot applied") {val p=Presentation(domain,"epoch-0");p.accept(reply("epoch-0","current",snapshot("8","New")));check((p.snapshot?.get("cursor") as? Map<*,*>)?.get("seq")=="8")}
    test("cursor counter preserves maxu64 without float") {val p=Presentation(domain,"epoch-0");p.accept(reply("epoch-0","current",snapshot("18446744073709551615","Max")));check((p.snapshot?.get("cursor") as? Map<*,*>)?.get("seq")=="18446744073709551615")}
    test("old numeric watermark not lexicographic cannot override") {val p=Presentation(domain,"epoch-0");p.accept(reply("epoch-0","current",snapshot("10","New")));p.accept(reply("epoch-0","current",snapshot("9","Old")));check((p.snapshot?.get("cursor") as? Map<*,*>)?.get("seq")=="10")}
    test("stale display never replaces current snapshot or raw") {val p=Presentation(domain,"epoch-1");p.draft=" Raw\uD800 ";p.accept(reply("epoch-1","current",snapshot("8","Current")));p.accept(reply("epoch-0","stale",snapshot("99","Stale")));check((p.snapshot?.get("cursor") as? Map<*,*>)?.get("seq")=="8" && p.draft==" Raw\uD800 ")}
    test("genuine stale receipt retained without regressing snapshot") {
        val p=Presentation(domain,"epoch-1");p.draft="New draft";p.currentIntent="new";p.accept(reply("epoch-1","current",snapshot("8","Current")))
        val business=Business("a","original","4","Raw");val plan=mapOf<String,Any?>("id" to "plan","intent" to "original","object_id" to "a","expected_revision" to "4","normalized_name" to "Normalized","parameters_digest" to "digest")
        val receipt=mapOf<String,Any?>("kind" to "synthetic","id" to "receipt","intent" to "original","object_id" to "a","expected_revision" to "4","result_revision" to "5","normalized_name" to "Normalized","parameters_digest" to "digest","commit_cursor" to (domain.wire()+mapOf("seq" to "5")))
        p.accept(reply("epoch-0","stale",snapshot("5","Earlier"),receipt),BoundPlan(domain,business,plan))
        check(p.receipts["original"]?.get("id")=="receipt");check((p.snapshot?.get("cursor") as? Map<*,*>)?.get("seq")=="8" && p.draft=="New draft")
    }
    println("RESULT $passed passed / $failed failed");check(failed==0)
}
