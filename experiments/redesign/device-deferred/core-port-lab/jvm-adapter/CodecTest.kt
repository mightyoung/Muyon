package muyon.rd.p05c

fun main() {
    var passed=0; var failed=0
    fun test(name:String, body:()->Unit) {try {body();println("PASS $name");passed++}catch(e:Throwable){println("FAIL $name: ${e.message}");failed++}}
    test("canonical u64 travels as string unchanged") {val v=mapOf("revision" to "18446744073709551615");check(Json.parse(Json.stringify(v))==v)}
    test("raw UTF16 units survive numeric array without normalization") {val raw=" \u000b e\u0301\uD800";val frame=Json.parse(Json.stringify(mapOf("raw_utf16" to raw.map {it.code}))) as? Map<*,*>;check((frame?.get("raw_utf16") as? List<*>)?.map {(it as JsonNumber).token.toInt()}==raw.map {it.code})}
    test("JSON duplicate keys are rejected") {check(runCatching {Json.parse("{\"a\":1,\"a\":2}")}.isFailure)}
    test("JSON trailing text is rejected") {check(runCatching {Json.parse("null false")}.isFailure)}
    test("string controls and escapes roundtrip") {val text="line\nquote\"\\中文";check(Json.parse(Json.stringify(text))==text)}
    test("JSON object null array boolean and number tokens parsed") {val map=Json.parse("{\"a\":[null,true,false,-2,1.5]}") as? Map<*,*>;check(map?.get("a")==listOf(null,true,false,JsonNumber("-2"),JsonNumber("1.5")))}
    println("RESULT $passed passed / $failed failed");check(failed==0)
}
