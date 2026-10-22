package com.mightyoung.muyon.androidlab

/** Nonsecret route preference; connection references are selected from trusted installations. */
data class SearchSettings(val enabled:Boolean=false,val provider:String="deepseek-search",val connection:String="",val revision:Long=1,val corrupt:Boolean=false)
data class SearchSettingsView(val settings:SearchSettings=SearchSettings(),val installedConnections:List<String> = emptyList(),val synthetic:Boolean=false,val message:String="")
interface SearchSettingsPort {
    fun read():SearchSettingsView
    /** Local-only save; no provider probe, handle resolution, grant or budget change. */
    fun save(enabled:Boolean,connection:String):SearchSettingsView
}
fun searchSettingsStatus(view:SearchSettingsView):String=when {
    view.settings.corrupt->"配置损坏 · 未就绪，请重新保存"
    !view.settings.enabled->"网页搜索已关闭"
    view.settings.connection.isEmpty()->"未配置连接 · 未就绪"
    view.synthetic->"合成连接已配置 · 等待私有 Service 核实"
    else->"SearchHost 未安装 · 未就绪"
}
data class ChatSource(val title:String,val url:String,val rank:Int)
data class ChatToolResult(val tool:String,val provider:String,val sources:List<ChatSource>,val currency:String,val costMicros:Long,val empty:Boolean,val tainted:Boolean=true,val instructionAuthority:Boolean=false) {
    init {
        require(tool.length in 1..128 && provider.length in 1..128 && sources.size<=50 && currency in setOf("USD","CNY") && costMicros>=0 && tainted && !instructionAuthority)
        require(empty==sources.isEmpty())
        sources.forEach { require(it.title.toByteArray().size<=4096 && it.rank in 1..50 && it.url.length<=4096 && (it.url.startsWith("https://")||it.url.startsWith("http://")) && !it.url.substringAfter("://").substringBefore('/').contains('@') && it.url.none{c->c.isISOControl()||c.isWhitespace()}) }
    }
}
