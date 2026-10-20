package com.mightyoung.muyon.androidlab.agentipc

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.text.InputType
import android.text.method.PasswordTransformationMethod
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import java.util.concurrent.Executors

/** Non-exported, agent-process-only local handover. No key Intent, regular file or network input. */
class OrdinaryChatCredentialActivity:Activity() {
    private lateinit var input:EditText
    private val executor=Executors.newSingleThreadExecutor()
    private val lifetime=Any()
    private var destroyed=false
    private var generation=0
    private var pipe:OrdinaryChatLocalCredentialPipe?=null
    private var pendingManual:CharArray?=null
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(null)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val root=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;setPadding(32,48,32,32);isSaveEnabled=false;importantForAutofill=View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS}
        val status=TextView(this).apply{text="DeepSeek chat canary · CNY\n临时密钥仅保留在本次 agent 进程。手动输入后清空输入框；不保存、不复制。费用上限人民币1元，最多2次，无重试。"}
        input=object:EditText(this) {
            override fun onTextContextMenuItem(id:Int):Boolean=false
        }.apply{
            hint="在本机手动输入临时 API key"
            inputType=InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            transformationMethod=PasswordTransformationMethod.getInstance()
            imeOptions=EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            isSaveEnabled=false;setSaveFromParentEnabled(false);importantForAutofill=View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            setTextIsSelectable(false);isLongClickable=false;setOnLongClickListener{true}
            filters=arrayOf(android.text.InputFilter.LengthFilter(512))
        }
        val ready=Button(this).apply{text="仅在本进程启用 CNY 小额聊天"}
        ready.setOnClickListener {
            // Cancellation is immediate, never queued behind the FIFO reader.
            pipe?.close();pipe=null
            val ticket=synchronized(lifetime){generation+=1;generation}
            val chars=CharArray(input.text.length)
            input.text.getChars(0,chars.size,chars,0);input.text.clear();ready.isEnabled=false
            synchronized(lifetime){pendingManual=chars}
            executor.execute {
                val ok=try{synchronized(lifetime){check(!destroyed && ticket==generation);(application as OrdinaryChatLiveApplication).installTemporaryCredential(this,chars)};true}catch(_:Exception){false}finally{synchronized(lifetime){chars.fill('\u0000');if(pendingManual===chars)pendingManual=null}}
                runOnUiThread{if(synchronized(lifetime){!destroyed && ticket==generation}){if(ok){status.text="临时凭据已在 agent 进程就绪。返回普通聊天。";finish()}else{status.text="安全入口未就绪；未发送请求。";ready.isEnabled=true}}}
            }
        }
        root.addView(status);root.addView(input);root.addView(ready);setContentView(root)
        if((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE)!=0 && android.os.Build.VERSION.SDK_INT>=27){
            val ticket=synchronized(lifetime){generation}
            pipe=OrdinaryChatLocalCredentialPipe(noBackupFilesDir,
                install={chars->synchronized(lifetime){check(!destroyed && ticket==generation);(application as OrdinaryChatLiveApplication).installTemporaryCredential(this,chars)}},
                finished={ok->runOnUiThread{if(synchronized(lifetime){!destroyed && ticket==generation}){status.text=if(ok)"临时凭据已在 agent 进程就绪。返回普通聊天。" else "本机交接已结束；未发送请求。仍可手动输入。";if(ok)finish()}}},
                ready={runOnUiThread{if(synchronized(lifetime){!destroyed && ticket==generation})status.text="本机临时交接入口已就绪（120秒）。也可手动输入；密钥不保存。未发送请求。"}})
            try{pipe?.start()}catch(_:Exception){pipe?.close();pipe=null;status.text="本机交接入口未就绪；仍可手动输入。未发送请求。"}
        }
    }
    override fun onSaveInstanceState(outState:Bundle){outState.clear()}
    override fun onPause(){input.text.clear();super.onPause()}
    override fun onDestroy(){
        synchronized(lifetime){destroyed=true;generation+=1;pendingManual?.fill('\u0000');pendingManual=null}
        pipe?.close();pipe=null
        input.text.clear();executor.shutdownNow();super.onDestroy()
    }
}
