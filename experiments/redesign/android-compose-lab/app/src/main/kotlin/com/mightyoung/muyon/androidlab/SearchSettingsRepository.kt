package com.mightyoung.muyon.androidlab

import android.content.Context
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile

private object SearchSettingsFileGate {val monitor=Any()}
/** Fresh bounded reads across UI/:agent processes. No key input or network API. */
internal class SearchSettingsRepository(context:Context,private val fixture:Boolean=false):SearchSettingsPort {
    private val root=File(context.filesDir.canonicalFile,"registered-tools-settings-v1").apply {check(exists()||mkdir());check(isDirectory && canonicalFile==absoluteFile)}
    private val atomic=AtomicFile(File(root,"settings.json"))
    private val connections get()=if(fixture)listOf("search-connection")else emptyList()
    private fun <T> locked(work:()->T):T=synchronized(SearchSettingsFileGate.monitor) {RandomAccessFile(File(root,"settings.lock"),"rw").use {file->file.channel.lock().use {work()}}}
    private fun load():SearchSettings {
        if(!atomic.baseFile.exists() && !File(root,"settings.json.bak").exists())return SearchSettings()
        val bytes=atomic.openRead().use { input->val buffer=ByteArray(1025);var count=0;while(count<buffer.size){val n=input.read(buffer,count,buffer.size-count);if(n<0)break;require(n>0);count+=n};buffer.copyOf(count) };require(bytes.size<=1024)
        val j=JSONObject(String(bytes,Charsets.UTF_8));require(j.keys().asSequence().toSet()==setOf("version","enabled","provider","connection","revision"))
        require(j.get("version") is Int && j.getInt("version")==1 && j.get("enabled") is Boolean && j.get("provider")=="deepseek-search" && j.get("connection") is String && (j.get("revision") is Int || j.get("revision") is Long))
        val ref=j.getString("connection");val rev=j.getLong("revision");require(ref in setOf("","search-connection") && rev in 1..9_007_199_254_740_991L)
        return SearchSettings(j.getBoolean("enabled"),connection=ref,revision=rev)
    }
    override fun read():SearchSettingsView=try {locked{SearchSettingsView(load(),connections,fixture)}}catch(_:Exception){SearchSettingsView(SearchSettings(corrupt=true),connections,fixture)}
    override fun save(enabled:Boolean,connection:String):SearchSettingsView=try {
        locked {
            require(connection.isEmpty()||connection in connections)
            val old=try{load()}catch(_:Exception){null};var revision:Long;do { revision=(java.security.SecureRandom().nextLong().ushr(11))+1 }while(revision==old?.revision || revision>9_007_199_254_740_991L)
            val j=JSONObject().put("version",1).put("enabled",enabled).put("provider","deepseek-search").put("connection",connection).put("revision",revision)
            var stream:java.io.FileOutputStream?=null
            try{stream=atomic.startWrite();stream.write(j.toString().toByteArray(Charsets.UTF_8));atomic.finishWrite(stream)}catch(e:Exception){if(stream!=null)atomic.failWrite(stream);throw e}
            SearchSettingsView(load(),connections,fixture,"已保存；未发送任何请求")
        }
    }catch(_:Exception){read().copy(message="保存失败；配置未确认生效")}
    /** Used only by trusted Service constructor; corrupt data stays explicitly invalid. */
    fun snapshotJson():String=try { locked {
        try{val s=load();JSONObject().put("version",1).put("enabled",s.enabled).put("provider",s.provider).put("connection",s.connection).put("revision",s.revision).toString()}catch(_:Exception){"{\"invalid\":true}"}
    }}catch(_:Exception){"{\"invalid\":true}"}
}
