package com.mightyoung.muyon.preview
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.ui.shell.*
import com.mightyoung.muyon.product.ui.system.*
import com.mightyoung.muyon.product.ui.configuration.*
import com.mightyoung.muyon.product.agents.setup.*
/** Isolated fixture renderer. No Internet permission, ProductClient, Service, binding or backend. */
class PreviewActivity: ComponentActivity() {
 override fun onCreate(state: Bundle?) {
  super.onCreate(state)
  val page=intent.getStringExtra("page") ?: "chat"
  setContent {
   FoundationTheme {
    Column(Modifier.fillMaxSize()) {
     Text("Compose组件预览 · 合成数据 · 043bed97\n非完整产品APK；无宿主/模型请求",Modifier.fillMaxWidth().padding(8.dp),style=MaterialTheme.typography.labelSmall)
     Box(Modifier.weight(1f)) {
      when(page) {
       "bot" -> {
        val editor=remember { BotConfigurationEditor(BotSetupDraft("component-preview-only")) }
        BotConfigurationScreen(editor,editor.draft.snapshot(),{})
       }
       "group" -> GroupConfigurationScreen(GroupGovernanceDisplay(null,null,null,null,null,null,emptyList()),null,null,"",null,{})
       else -> ConversationShell("chat","Muyon 主 Agent（预览）","preview-main", listOf(ShellConversation("preview-main","Muyon 主 Agent（预览）",main=true)),{},{},{}) { open ->
        Column(Modifier.fillMaxSize()) {
         ConversationHeader("Muyon 主 Agent",open,mainAgent=true)
         Column(Modifier.weight(1f).padding(16.dp)) {
          Text("当前为组件预览，不含真实会话历史。",style=MaterialTheme.typography.bodyMedium)
          if(page=="cards") ReadOnlySnapshotPanel(null,"没有接入可信业务事实；操作不可用。",false,null)
         }
         var draft by remember { mutableStateOf("") }
         ShellInputDock(draft,{draft=it},false,{}, {},{})
        }
       }
      }
     }
    }
   }
  }
 }
}
