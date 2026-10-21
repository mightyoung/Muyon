package com.mightyoung.muyon.product.research

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.ml.SearchHit
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

@Composable
internal fun LocalResearchPanel(host: ResearchFileHost, project: String, paper: JSONObject?, enabled: Boolean) {
    val context = LocalContext.current.applicationContext
    val local = remember(host, project) { LocalResearch(context, host) }
    var query by remember(project) { mutableStateOf("") }
    var status by remember(project) { mutableStateOf("") }
    var hits by remember(project) { mutableStateOf<List<SearchHit>>(emptyList()) }
    var pending by remember(project) { mutableStateOf<AtomicBoolean?>(null) }
    DisposableEffect(local) {
        host.ownModel(local)
        onDispose { pending?.set(true); host.releaseModel(local) }
    }
    fun <T> run(action: (AtomicBoolean) -> T, done: (T) -> Unit) {
        if (pending != null) return
        val token = AtomicBoolean(false)
        pending = token
        status = "正在本机处理…"
        host.run({ action(token) }) { result ->
            if (pending === token) {
                pending = null
                result.onSuccess(done).onFailure {
                    status = if (token.get()) "已取消，未发布新索引" else it.message ?: "本地模型处理失败"
                }
            }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        HorizontalDivider()
        Text("本地语义检索", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(query, { query = it }, enabled = enabled && pending == null,
            label = { Text("搜索论文内容") }, modifier = Modifier.fillMaxWidth().testTag("research-semantic-query"))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(enabled = enabled && pending == null && query.isNotBlank(), onClick = {
                hits = emptyList()
                run({ local.search(project, query, it) }) { result -> hits = result; status = "找到 ${result.size} 个片段" }
            }, modifier = Modifier.testTag("research-semantic-search")) { Text("搜索") }
            if (pending != null) TextButton(onClick = { pending?.set(true); status = "正在取消…" }, modifier = Modifier.testTag("research-index-cancel")) { Text("取消") }
        }
        paper?.let { detail ->
            val attachments = detail.optJSONArray("attachments")
            for (index in 0 until (attachments?.length() ?: 0)) {
                TextButton(enabled = enabled && pending == null, onClick = {
                    val paperId = detail.getString("id")
                    val digest = requireNotNull(attachments).getJSONObject(index).getString("digest")
                    run({ local.index(project, paperId, digest, it) }) { count -> status = "本地索引已建立 · $count 个片段" }
                }, modifier = Modifier.testTag("research-index-$index")) { Text("识别附件 ${index + 1} 并建立索引") }
            }
        }
        if (pending != null) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (status.isNotEmpty()) Text(status, Modifier.testTag("research-semantic-status"), style = MaterialTheme.typography.bodySmall)
        hits.forEach { hit ->
            Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, shape = MaterialTheme.shapes.medium) {
                Column(Modifier.padding(12.dp)) {
                    Text("论文 ${hit.source.paper} · 第 ${hit.page + 1} 页", style = MaterialTheme.typography.labelMedium)
                    Text(hit.text, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}
