package com.mightyoung.muyon.androidlab.agentipc

import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject

/** Called inside the SAME owner's authority guard and transaction before handoff. */
internal fun ordinaryContextAllowed(db:SQLiteDatabase,state:ServiceAdmissionAuthority.State,context:ByteArray,payload:ByteArray):Boolean = try {
    val ctx=JSONObject(String(context,Charsets.UTF_8));val body=JSONObject(String(payload,Charsets.UTF_8))
    val a=checkNotNull(state.chat)
    fun closed(o:JSONObject,keys:Set<String>)=o.keys().asSequence().toSet()==keys
    check(closed(body,setOf("model","messages","n","stream","max_tokens")))
    check(body.getString("model")==state.provider?.profile?.model && body.getInt("n")==1 && !body.getBoolean("stream") && body.getLong("max_tokens") in 1..1024)
    val base=setOf("authority","workspace","conversation","input_ref","task","attempt","input_version")
    fun history(c:JSONObject):JSONArray {
        if(c.has("history") || c.has("history_version")) {
            check(closed(c,base+setOf("history","history_version")) && c.getString("history_version")=="ordinary-context-v1")
            return c.getJSONArray("history").also {check(it.length()<=8)}
        }
        check(closed(c,base));return JSONArray()
    }
    val rows=history(ctx)
    fun authority(auth:JSONObject):Boolean {
        val expected=mapOf("workspace" to a.workspace,"conversation" to ctx.getString("conversation"),"owner" to a.owner,"mode" to a.mode,"policy_revision" to a.policyRevision,"grant_revision" to a.grantRevision,"input_rule" to a.ruleRevision,"restriction_revision" to a.restrictionRevision,"sensitivity" to a.sensitivity,"output_rule" to "MODEL-TEXT-v1")
        return closed(auth,expected.keys+"synthetic") && expected.all{(k,v)->auth.opt(k)==v} && auth.opt("synthetic")==true
    }
    check(ctx.getString("workspace")==a.workspace && authority(ctx.getJSONObject("authority")))
    check(ctx.getString("input_version")=="utf8-exact-v1")
    val seen=linkedMapOf<String,JSONObject>()
    for(i in 0 until rows.length()) {
        val row=rows.getJSONObject(i)
        check(closed(row,setOf("request","run","epoch","build","task","attempt","input_ref","receipt","authority","user","answer","ancestors")))
        val run=row.getString("run");check(Regex("[0-9a-f]{32}").matches(run) && run !in seen)
        check(Regex("[0-9a-f]{32}").matches(row.getString("epoch")) && Regex("[0-9a-f]{40}").matches(row.getString("build")))
        check(Regex("[A-Za-z0-9_-]{1,64}").matches(row.getString("request")))
        for(key in listOf("task","attempt","input_ref","receipt"))check(row.getString(key).let {it.isNotBlank() && it.length<=512 && it.none(Char::isISOControl)})
        check(row.getString("input_ref")==run+":"+row.getString("request"))
        check(authority(row.getJSONObject("authority")))
        check(ordinaryTextSupported(row.getString("user")) && ordinaryTextSupported(row.getString("answer")))
        val ancestors=row.getJSONArray("ancestors");val ordered=mutableListOf<String>()
        for(n in 0 until ancestors.length()) {
            val id=ancestors.getString(n);check(id in seen && id !in ordered);ordered+=id
        }
        check(ordered==seen.keys.filter { it in ordered })
        db.rawQuery("SELECT r.request_id,r.payload,r.state,f.context,t.context FROM admissions a JOIN reservations r ON r.token=a.token JOIN chat_contexts f ON f.token=r.token JOIN chat_attempts t ON t.id=a.id WHERE a.id=?",arrayOf(row.getString("receipt"))).use { old->
            check(old.moveToFirst() && old.getString(2)=="consumed")
            check(old.getBlob(0).contentEquals(ordinaryRequestIdBytes(row.getString("request"))))
            check(old.getBlob(3).contentEquals(old.getBlob(4)))
            val source=JSONObject(String(old.getBlob(3),Charsets.UTF_8))
            for(k in listOf("task","attempt","input_ref"))check(source.getString(k)==row.getString(k))
            check(source.getString("workspace")==a.workspace && source.getString("conversation")==ctx.getString("conversation"))
            check(jsonSame(source.getJSONObject("authority"),row.getJSONObject("authority")))
            val inherited=history(source);check(inherited.length()==ordered.size)
            for(n in 0 until inherited.length()) {
                val unit=inherited.getJSONObject(n)
                check(unit.getString("run")==ordered[n] && jsonSame(unit,checkNotNull(seen[ordered[n]])))
            }
            val wire=JSONObject(String(old.getBlob(1),Charsets.UTF_8)).getJSONArray("messages")
            check(wire.length()==inherited.length()*2+1)
            for(n in 0 until inherited.length()) {
                checkMessage(wire.getJSONObject(n*2),"user",inherited.getJSONObject(n).getString("user"))
                checkMessage(wire.getJSONObject(n*2+1),"assistant",inherited.getJSONObject(n).getString("answer"))
            }
            checkMessage(wire.getJSONObject(wire.length()-1),"user",row.getString("user"))
        }
        seen[run]=row
    }
    val messages=body.getJSONArray("messages");check(messages.length()==rows.length()*2+1)
    for(i in 0 until rows.length()) {
        checkMessage(messages.getJSONObject(i*2),"user",rows.getJSONObject(i).getString("user"))
        checkMessage(messages.getJSONObject(i*2+1),"assistant",rows.getJSONObject(i).getString("answer"))
    }
    val last=messages.getJSONObject(messages.length()-1)
    checkMessage(last,"user",last.getString("content"))
    check(ordinaryTextSupported(last.getString("content")))
    true
}catch(_:Exception){false}

private fun checkMessage(message:JSONObject,role:String,text:String) {
    check(message.keys().asSequence().toSet()==setOf("role","content") && message.get("role")==role && message.get("content")==text)
}
private fun jsonSame(left:Any?,right:Any?):Boolean = when {
    left is JSONObject && right is JSONObject -> left.keys().asSequence().toSet()==right.keys().asSequence().toSet() && left.keys().asSequence().all{jsonSame(left.get(it),right.get(it))}
    left is JSONArray && right is JSONArray -> left.length()==right.length() && (0 until left.length()).all{jsonSame(left.get(it),right.get(it))}
    else -> left==right
}
