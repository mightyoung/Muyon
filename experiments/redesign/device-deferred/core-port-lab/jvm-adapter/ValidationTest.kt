package muyon.rd.p05c
fun main(){
 val d=Domain("store","scope","stream")
 val b=Business("a","original","4"," Raw ")
 val plan=mapOf<String,Any?>("id" to "plan","intent" to b.intent,"object_id" to b.objectId,"expected_revision" to b.expectedRevision,"normalized_name" to "Name","parameters_digest" to "correct")
 val receipt=mapOf<String,Any?>("kind" to "synthetic","id" to "receipt","intent" to b.intent,"object_id" to b.objectId,"expected_revision" to b.expectedRevision,"result_revision" to "5","normalized_name" to "Name","parameters_digest" to "correct","commit_cursor" to (d.wire()+mapOf("seq" to "5")))
 fun wire(kind:String,r:Map<String,Any?>?,id:String="q",epoch:String="epoch-0",reason:String?=null)=mapOf<String,Any?>("protocol" to 0,"request_id" to id,"kind" to kind,"reason" to reason,"domain" to d.wire(),"display_epoch" to epoch,"display_admission" to "current","snapshot" to null,"plan" to null,"receipt" to r)
 var failures=0;var passes=0
 fun test(name:String,body:()->Unit){try{body();passes++;println("PASS $name")}catch(e:Throwable){failures++;println("FAIL $name: ${e.message}")}}
 test("committed requires receipt at strict decoder"){check(runCatching{Reply.parse(Json.stringify(wire("committed",null)),"q")}.isFailure){"committed null receipt accepted"}}
 test("unknown must not carry successful receipt"){check(runCatching{Reply.parse(Json.stringify(wire("unknown",receipt)),"q")}.isFailure){"unknown with successful receipt accepted"}}
 test("sanitized invalid_request cannot carry effect data"){check(runCatching{Reply.parse(Json.stringify(wire("rejected",receipt,"","","invalid_request")),"q")}.isFailure){"uncorrelated invalid_request receipt accepted"}}
 test("digest mismatch cannot report committed UI status"){
  val p=Presentation(d,"epoch-0");p.currentIntent=b.intent;p.draft=b.raw
  val r=Reply.parse(Json.stringify(wire("committed",receipt+mapOf("parameters_digest" to "wrong"))),"q")
  p.accept(r,BoundPlan(d,b,plan));println("PROBE mismatch status=${p.status} ledger=${p.receipts.size}")
  check(p.receipts.isEmpty());check(p.status!="committed"){"unbound effect projected committed despite no verified receipt"}
 }
 test("sanitized invalid_request rejects snapshot and plan independently") {
  val snapshot=mapOf("cursor" to (d.wire()+mapOf("seq" to "0")),"suppliers" to listOf(mapOf("id" to "a","name" to "Name","revision" to "4")))
  for(patch in listOf(mapOf("snapshot" to snapshot),mapOf("plan" to plan))) {
   check(runCatching {Reply.parse(Json.stringify(wire("rejected",null,"","","invalid_request")+patch),"q")}.isFailure){"sanitized data payload accepted"}
  }
 }
 test("verified committed receipt with null snapshot accounts effect without projection") {
  val p=Presentation(d,"epoch-0");p.currentIntent=b.intent;p.draft=b.raw
  val reply=Reply.parse(Json.stringify(wire("committed",receipt)),"q")
  p.accept(reply,BoundPlan(d,b,plan));check(p.receipts[b.intent]?.get("id")=="receipt" && p.status=="committed")
  check(p.snapshot==null && p.draft==b.raw){"receipt fabricated projection/raw"}
 }
 test("unknown reply_limit keeps no receipt projection") {
  val reply=Reply.parse(Json.stringify(wire("unknown",null,reason="reply_limit")),"q")
  val p=Presentation(d,"epoch-0");p.currentIntent=b.intent;p.draft=b.raw;p.accept(reply,BoundPlan(d,b,plan))
  check(p.status=="unknown" && p.receipts.isEmpty() && p.snapshot==null && p.draft==b.raw)
 }
 println("RESULT ${passes} passed / $failures failed");check(failures==0)
}
