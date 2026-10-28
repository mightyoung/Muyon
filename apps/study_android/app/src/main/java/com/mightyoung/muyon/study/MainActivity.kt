package com.mightyoung.muyon.study

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import org.json.JSONArray
import org.json.JSONObject
import com.mightyoung.muyon.study.adapters.*
import java.util.concurrent.Executors

class MainActivity:ComponentActivity(){
    private lateinit var repo:StudyRepository
    private lateinit var speech:OfflineSpeech
    private val session by lazy { androidx.lifecycle.ViewModelProvider(this)[StudySession::class.java] }
    private val io get()=session.io
    private var state:JSONObject get()=session.state
        set(v){session.state=v}
    private var notice:String get()=session.notice
        set(v){session.notice=v}
    private var busy:Boolean get()=session.busy
        set(v){session.busy=v}
    private var preview:JSONObject? get()=session.preview
        set(v){try{session.updatePreview(v)}catch(e:Exception){session.notice=e.message?:"预览保存失败"}}
    private var voiceText:String? get()=session.voiceText
        set(v){session.voiceText=v}
    private var googleToken:String? get()=session.googleToken
        set(v){session.googleToken=v}
    private var afterGoogle:(()->Unit)? get()=session.afterGoogle
        set(v){session.afterGoogle=v}
    private var importKind="plan"
    private val picker=registerForActivityResult(ActivityResultContracts.OpenDocument()){uri->if(uri!=null)background{
        val name=contentResolver.query(uri,arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),null,null,null)?.use{if(it.moveToFirst())it.getString(0)else null}?:"upload"
        when(importKind){
            "resource"-> {val resource=StudyFiles.saveResource(this,uri);runOnUiThread{dispatch(obj("op" to "upsert","kind" to "resources","value" to resource))}}
            "restore"->{val data=contentResolver.openInputStream(uri)!!.use{StudyFiles.readBackup(this,it)};runOnUiThread{preview=obj("mode" to "restore","title" to "恢复备份","summary" to "将替换本机学习数据；建议先导出当前备份。账号密钥不会恢复。","data" to data,"items" to JSONArray())}}
            else->{val bytes=contentResolver.openInputStream(uri)!!.use{input->val out=java.io.ByteArrayOutputStream();val b=ByteArray(8192);while(true){val n=input.read(b);if(n<0)break;require(out.size()+n<=24*1024*1024){"导入文件超过24MB"};out.write(b,0,n)};out.toByteArray()}
                val papers=importKind=="paper"
                val data=if(papers){val raw=String(bytes,Charsets.UTF_8).removePrefix("\uFEFF");if(raw.trim().startsWith("["))JSONArray(raw)else JSONArray().put(JSONObject(raw))}else PlanImport.parse(name,bytes)
                require(data.length()>0){"没有识别到可导入的内容"}
                runOnUiThread{preview=obj("mode" to if(papers)"papers" else "tasks","title" to if(papers)"导入题包" else "导入学习计划","summary" to "$name · ${data.length()} 项，确认后保存；重复ID保留原记录。","items" to data,"data" to data)}
            }
        }
    }}
    private val export=registerForActivityResult(ActivityResultContracts.CreateDocument("application/zip")){uri->if(uri!=null){val frozen=JSONObject(state.toString());background{contentResolver.openOutputStream(uri)!!.use{StudyFiles.exportBackup(this,frozen,it)};tell("备份已导出，包含任务、作答和上传附件")}}}
    private val mic=registerForActivityResult(ActivityResultContracts.RequestPermission()){allowed->if(allowed)startSpeech()else tell("未授予麦克风权限，可继续文字输入")}
    private val notifications=registerForActivityResult(ActivityResultContracts.RequestPermission()){tell(if(it)DueReminders.reconcile(this,state.optJSONArray("tasks")?:JSONArray()) else "未允许通知，任务仍已保存")}
    private val googleResult=registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()){r->
        try{val result=GoogleAuthorization.resultFromIntent(this,requireNotNull(r.data));googleToken=result.accessToken;BackgroundSync.googleConnected(this);val next=afterGoogle;afterGoogle=null;if(googleToken.isNullOrBlank())tell("Google 未返回访问凭据")else if(next!=null)next()else tell("Google 授权已完成，请重新点击需要的同步操作")}catch(_:Exception){tell("Google 授权未完成，请核对账号与 OAuth 配置")}
    }
    override fun onCreate(savedInstanceState:Bundle?){super.onCreate(savedInstanceState);enableEdgeToEdge();repo=StudyRepository.get(this);speech=OfflineSpeech(this);importKind=savedInstanceState?.getString("importKind")?:"plan";refresh()
        setContent{StudyUi(state,notice,busy,voiceText,
            dispatch={c->dispatch(c)},onNotice={tell(it)},
            onImport={kind->importKind=kind;picker.launch(arrayOf("*/*"))},
            onExport={export.launch("muyon-study-${java.time.LocalDate.now()}.zip")},
            onVoice={voiceText="";if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)==android.content.pm.PackageManager.PERMISSION_GRANTED)startSpeech()else mic.launch(Manifest.permission.RECORD_AUDIO)},
            onVoiceDismiss={speech.stop();voiceText=null},
            onMaimemo={background("maimemo"){val p=Providers.maimemo(SecureKeys.get(this,"maimemo"));runOnUiThread{dispatch(obj("op" to "maimemo_sync","progress" to p,"now" to System.currentTimeMillis()))}}},
            onGoogle={authorize(false){background("calendar"){val events=Providers.calendar(googleToken!!,System.currentTimeMillis()-86400000L,System.currentTimeMillis()+120L*86400000L);runOnUiThread{dispatch(obj("op" to "calendar_sync","events" to events,"now" to System.currentTimeMillis()))}}}},
            onPublish={authorize(true){background{val result=Providers.publishSchedule(googleToken!!,state.optJSONArray("schedule")?:JSONArray());tell("日历：新增 ${result.optInt("created")}，保持 ${result.optInt("unchanged")}，清理 ${result.optInt("deleted")}，冲突 ${result.optJSONArray("conflicts")?.length()?:0}；请同步后核对")}}},
            onDriveBackup={authorize(false){val frozen=JSONObject(state.toString());background{val file=java.io.File(cacheDir,"backup-${newId()}.zip");try{file.outputStream().use{StudyFiles.exportBackup(this,frozen,it)};val id=Providers.driveBackupFile(googleToken!!,"muyon-study-${java.time.LocalDate.now()}.zip",file);tell("云盘备份已创建：$id")}finally{file.delete()}}}},
            onDriveFiles={authorize(false){background("drive"){val files=Providers.driveFiles(googleToken!!);runOnUiThread{preview=obj("mode" to "drive","title" to "云盘文件","summary" to "仅显示本应用已获得访问权限的文件。","items" to files)}}}},
            onDriveSelect={file->authorize(false){background{
                val staging=java.io.File(cacheDir,"drive-${newId()}")
                try{staging.outputStream().use{Providers.driveDownloadTo(googleToken!!,file.getString("id"),it)}
                    if(file.optString("name").endsWith(".zip",true)){
                        val restored=staging.inputStream().use{StudyFiles.readBackup(this,it)};runOnUiThread{preview=obj("mode" to "restore","title" to "恢复云盘备份","summary" to "确认后替换本地学习数据。请先导出当前备份。","data" to restored,"items" to JSONArray())}
                    }else{require(staging.length()<=64L*1024*1024){"单个资源超过64MB"};val safe=file.optString("name","云盘资料").replace(Regex("[^\\p{L}\\p{N}._ -]"),"_").take(160).ifBlank{"资料"};val target=java.io.File(filesDir,"resources/${newId()}/$safe");target.parentFile!!.mkdirs();staging.copyTo(target);val r=obj("id" to newId(),"title" to file.optString("name"),"type" to "file","path" to target.relativeTo(filesDir).path,"mime" to file.optString("mimeType","application/octet-stream"),"size" to target.length(),"driveId" to file.getString("id"));runOnUiThread{dispatch(obj("op" to "upsert","kind" to "resources","value" to r));preview=null}}
                }finally{staging.delete()}
            }}},
            onAi={prompt,attempt->val base=JSONObject(state.toString());background{val context=if(attempt==null)"\n已有任务（更新任务必须保留原id，只返回必要变化；禁止虚构完成）：${(base.optJSONArray("tasks")?:JSONArray()).toString().take(12000)}" else "";val answer=Providers.deepSeek(SecureKeys.get(this,"deepseek"),SecureKeys.get(this,"model").ifBlank{"deepseek-chat"},prompt+context);val data=JSONObject(answer)
                val tasks=if(attempt==null)taskSuggestions(base,data.optJSONArray("tasks")?:JSONArray())else JSONArray()
                runOnUiThread{if(attempt!=null){dispatch(obj("op" to "commentary","attempt" to attempt,"text" to data.optString("commentary",data.optString("summary"))))}else{
                    preview=obj("mode" to "suggestions","baseRevision" to base.optLong("revision"),"title" to "AI 建议 · 待确认","summary" to data.optString("summary","请检查内容、时长及截止时间"),"items" to tasks,"data" to tasks)
                }}
            }},onLoadSample={background{val papers=JSONArray(assets.open("mem-papers.json").bufferedReader().use{it.readText()});runOnUiThread{preview=obj("mode" to "papers","title" to "附件一题包","summary" to "原附件不含标准答案，可作答、导出及AI辅助点评。","items" to papers,"data" to papers)}}},
            onSaveKey={name,value->try{SecureKeys.set(this,name,value);if(name=="maimemo"&&value.isNotBlank())BackgroundSync.enable(this);tell("凭据已保存到系统密钥保护存储")}catch(_:Exception){tell("凭据保存失败")}},
            preview=preview,onDismissPreview={preview=null},onConfirmPreview={confirmPreview()})}
    }
    private fun startSpeech(){speech.start(onText={voiceText=it},onStatus={tell(it)})}
    private fun refresh(){repo.request(obj("op" to "snapshot")){data,error->if(data!=null){state=data;notice="已保存到本机 · 离线可用"}else notice=error?:"无法加载"}}
    private fun dispatch(command:JSONObject){busy=true;repo.request(command){_,error->busy=false;if(error!=null){tell(error)}else{refresh();if(command.optString("op") in listOf("upsert","delete","restore","import_tasks","apply_suggestions","calendar_sync","settings","lock_block")){repo.request(obj("op" to "snapshot")){data,_->if(data!=null){state=data;tell(DueReminders.reconcile(this,data.optJSONArray("tasks")?:JSONArray()));if(android.os.Build.VERSION.SDK_INT>=33&&data.items("tasks").any{it.optLong("due")>System.currentTimeMillis()}&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED)notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
                    try{if(data.items("tasks").isNotEmpty())repo.request(planningRequest(data)){_,e->if(e==null)refresh()else tell(e)}}catch(e:Exception){tell(e.message?:"请检查固定时段")}
                }}}}
    }}
    private fun confirmPreview(){val p=preview?:return;when(p.optString("mode")){
        "papers"->dispatch(obj("op" to "import_papers","papers" to p.getJSONArray("data")))
        "tasks"->dispatch(obj("op" to "import_tasks","tasks" to p.getJSONArray("data")))
        "suggestions"->dispatch(obj("op" to "apply_suggestions","expectedRevision" to p.optLong("baseRevision"),"tasks" to p.getJSONArray("data")))
        "restore"->dispatch(obj("op" to "restore","backup" to p.getJSONObject("data")))
    };preview=null}
    private fun authorize(write:Boolean,next:()->Unit){afterGoogle=next
        val callback:(com.google.android.gms.auth.api.identity.AuthorizationResult?,String?)->Unit={result,error->
            if(error!=null)tell(error)else if(result!=null){if(result.hasResolution()){val pending=result.pendingIntent;if(pending!=null)googleResult.launch(IntentSenderRequest.Builder(pending).build())else tell("Google 授权结果无效")}else{googleToken=result.accessToken;BackgroundSync.googleConnected(this);afterGoogle=null;if(googleToken.isNullOrBlank())tell("没有访问凭据")else next()}}
        }
        if(write)GoogleAuthorization.authorizeWrite(this,callback)else GoogleAuthorization.authorize(this,callback)
    }
    private fun background(provider:String?=null,run:()->Unit){busy=true;io.execute{try{run()}catch(e:Exception){val message=e.message?:"操作失败，本地内容仍然保留";if(provider!=null)repo.request(obj("op" to "sync_error","provider" to provider,"error" to message)){_,_->refresh()};tell(message)}finally{runOnUiThread{busy=false}}}}
    private fun tell(message:String){runOnUiThread{notice=message}}
    override fun onResume(){super.onResume();if(::repo.isInitialized)refresh()}
    override fun onStop(){super.onStop();speech.stop()}
    override fun onSaveInstanceState(outState:Bundle){outState.putString("importKind",importKind);super.onSaveInstanceState(outState)}
    override fun onDestroy(){speech.close();super.onDestroy()}
}
