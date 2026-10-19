package com.mightyoung.muyon.androidlab.agentipc

import android.app.Activity
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

/** Non-exported, agent-process-only, masked local handover. No Intent/clipboard/file key input. */
class OrdinaryChatCredentialActivity:Activity() {
    private lateinit var input:EditText
    private val executor=Executors.newSingleThreadExecutor()
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
        }
        val ready=Button(this).apply{text="仅在本进程启用 CNY 小额聊天"}
        ready.setOnClickListener {
            val chars=CharArray(input.text.length)
            input.text.getChars(0,chars.size,chars,0);input.text.clear();ready.isEnabled=false
            executor.execute {
                val ok=try{(application as OrdinaryChatLiveApplication).installTemporaryCredential(this,chars);true}catch(_:Exception){false}finally{chars.fill('\u0000')}
                runOnUiThread{if(ok){status.text="临时凭据已在 agent 进程就绪。返回普通聊天。";finish()}else{status.text="安全入口未就绪；未发送请求。";ready.isEnabled=true}}
            }
        }
        root.addView(status);root.addView(input);root.addView(ready);setContentView(root)
    }
    override fun onSaveInstanceState(outState:Bundle){outState.clear()}
    override fun onPause(){input.text.clear();super.onPause()}
    override fun onDestroy(){input.text.clear();executor.shutdown();super.onDestroy()}
}
