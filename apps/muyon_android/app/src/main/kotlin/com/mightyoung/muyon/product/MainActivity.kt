package com.mightyoung.muyon.product

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.supplier.SupplierScreen
import com.mightyoung.muyon.product.research.ResearchScreen
import com.mightyoung.muyon.product.chat.ChatScreen

class MainActivity : ComponentActivity() {
    private lateinit var client: ProductClient
    private var connected by mutableStateOf(false)
    private var initialized by mutableStateOf(false)
    private var existing by mutableStateOf(false)
    private var status by mutableStateOf("正在连接本地内核")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        client = ProductClient(this) { ready ->
            connected = ready
            if (ready) { existing = client.workspaceExists; client.call("health") { reply ->
                initialized = reply.optString("status") == "ok"
                status = if (initialized) "本地工作台已连接" else if (existing) "工作台暂不可用，请重试连接" else "请创建新工作台"
            } } else { initialized = false; status = "连接已断开；未确认的操作请查询原结果" }
        }
        setContent {
            MaterialTheme {
                var tab by remember { mutableStateOf("supplier") }
                Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("Muyon", style = MaterialTheme.typography.headlineMedium)
                        Text(status)
                        if (connected && !initialized) Button(onClick = {
                            client.call(if (existing) "health" else "initialize") { reply ->
                                initialized = reply.optString("status") == "ok"
                                if (initialized) existing = true
                                status = if (initialized) "本地工作台已连接" else reply.optString("error")
                            }
                        }) { Text(if (existing) "重试连接" else "创建新工作台") }
                        if (connected && initialized) {
                            Row {
                                Button(onClick = { tab = "supplier" }) { Text("供应商") }
                                Spacer(Modifier.width(8.dp))
                                Button(onClick = { tab = "research" }) { Text("科研工作台") }
                                Button(onClick = { tab = "chat" }) { Text("助手") }
                            }
                            when (tab) {
                                "supplier" -> SupplierScreen(client)
                                "research" -> ResearchScreen(client)
                                else -> ChatScreen(client, getSharedPreferences("muyon_product_research_v2", 0).getString("project_id", null))
                            }
                        }
                    }
                }
            }
        }
        client.bind()
    }
    override fun onDestroy() { client.close(); super.onDestroy() }
}
