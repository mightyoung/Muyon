package com.mightyoung.muyon.study

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import uniffi.muyon_study.StudyEngine

/** Single process-wide native owner and serial command queue. No Activity-owned database. */
class StudyRepository private constructor(context:Context) {
    private val worker=Executors.newSingleThreadExecutor()
    private val main=Handler(Looper.getMainLooper())
    private val root=context.applicationContext
    private var engine:StudyEngine?=null
    fun request(command:JSONObject,done:(JSONObject?,String?)->Unit) {
        worker.execute {
            try {
                val core=engine?:StudyEngine.open(java.io.File(root.filesDir,"study-v1.sqlite").absolutePath).also{engine=it}
                val reply=JSONObject(core.request(command.toString()))
                if(!reply.optBoolean("ok")) error(reply.optString("error","操作失败"))
                val value=reply.opt("data")
                val data=if(value is JSONObject)value else JSONObject().put("value",value)
                main.post{done(data,null)}
            }catch(e:Exception){main.post{done(null,e.message?:"本地服务不可用")}}
        }
    }
    companion object {
        @Volatile private var instance:StudyRepository?=null
        fun get(context:Context):StudyRepository=instance?:synchronized(this){instance?:StudyRepository(context).also{instance=it}}
    }
}
fun JSONArray.objects():List<JSONObject> =(0 until length()).mapNotNull{optJSONObject(it)}
fun JSONObject.items(key:String)=optJSONArray(key)?.objects().orEmpty()
fun obj(vararg pairs:Pair<String,Any?>)=JSONObject().also{j->pairs.forEach{j.put(it.first,it.second)}}
fun newId()=java.util.UUID.randomUUID().toString()
