package com.mightyoung.muyon.study
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.compose.runtime.*
import org.json.JSONObject
import java.util.concurrent.Executors

/** Owns pending UI results across Activity recreation; previews survive process restart. */
class StudySession(app:Application):AndroidViewModel(app){
    val io=Executors.newSingleThreadExecutor()
    var state by mutableStateOf(JSONObject())
    var notice by mutableStateOf("正在打开本地数据")
    var busy by mutableStateOf(false)
    var voiceText by mutableStateOf<String?>(null)
    var googleToken:String?=null
    var afterGoogle:(()->Unit)?=null
    private val pending=java.io.File(app.filesDir,"pending-review.json")
    var preview by mutableStateOf<JSONObject?>(try{if(pending.isFile&&pending.length()<25L*1024*1024)JSONObject(pending.readText())else null}catch(_:Exception){null})
    fun updatePreview(value:JSONObject?){
        if(value==null){pending.delete();preview=null;return}
        val temp=java.io.File(pending.parentFile,"pending-review.tmp");temp.writeText(value.toString());check(temp.renameTo(pending)){"待确认内容保存失败"};preview=value
    }
    override fun onCleared(){io.shutdown();super.onCleared()}
}
