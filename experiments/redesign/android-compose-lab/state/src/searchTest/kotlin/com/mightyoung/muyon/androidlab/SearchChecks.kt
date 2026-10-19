package com.mightyoung.muyon.androidlab

fun main() {
    var checks=0
    fun verify(name:String,body:()->Boolean){check(body()){name};println("PASS $name");checks++}
    val default=SearchSettingsView()
    verify("default disabled and no installed connection"){!default.settings.enabled && default.installedConnections.isEmpty() && searchSettingsStatus(default)=="网页搜索已关闭"}
    verify("enabled unconfigured remains unready"){searchSettingsStatus(default.copy(settings=SearchSettings(enabled=true))).contains("未就绪")}
    verify("configured without host remains unready"){searchSettingsStatus(default.copy(settings=SearchSettings(enabled=true,connection="search-connection"))).contains("SearchHost 未安装")}
    verify("synthetic configuration does not claim remote availability"){searchSettingsStatus(default.copy(settings=SearchSettings(enabled=true,connection="search-connection"),synthetic=true)).contains("等待私有 Service")}
    verify("corruption never becomes disabled"){searchSettingsStatus(default.copy(settings=SearchSettings(corrupt=true))).contains("配置损坏")}
    val result=ChatToolResult("web_search.search","deepseek-search",listOf(ChatSource("fixture","https://example.org/source",1)),"USD",750,false)
    val original=ChatReadConversation(requestId="request",runId="run",admittedServiceEpoch="old-epoch",answer="answer",receipt="receipt",status="completed",originalReceiptIdentity="identity",toolResult=result,toolReceipt=true)
    val lost=original.disclosureLost("lost")
    verify("loss clears every derived disclosure but preserves original identities"){lost.answer.isEmpty()&&lost.toolResult==null&&!lost.toolReceipt&&lost.receipt==null&&lost.runId==original.runId&&lost.admittedServiceEpoch=="old-epoch"&&lost.originalReceiptIdentity=="identity"}
    var submits=0
    val port=object:ChatReadPort {override var snapshot=ChatReadView();override fun submit(conversationId:String,text:String){submits++};override fun cancel(conversationId:String){};override fun reconcile(conversationId:String){}}
    val localStore=object:SearchSettingsPort {var value=default;override fun read()=value;override fun save(enabled:Boolean,connection:String)=value.copy(settings=SearchSettings(enabled=enabled,connection=connection,revision=2)).also{value=it}}
    localStore.save(true,"")
    verify("saving settings cannot submit a chat or search"){submits==0}
    verify("existing ordinary Send remains the only frontend dispatch"){frontendSubmit(port,"conversation","query")&&submits==1}
    verify("unknown cannot auto resend"){!frontendCanSend("query",lost.status)}
    verify("tainted result cannot promote instruction authority"){runCatching{result.copy(instructionAuthority=true)}.isFailure}
    verify("credential-bearing source URL rejected"){runCatching{result.copy(sources=listOf(ChatSource("fixture","https://user:pass@example.org",1)))}.isFailure}
    verify("empty success matches actual empty sources"){ChatToolResult("web_search.search","deepseek-search",emptyList(),"USD",0,true).empty}
    println("SEARCH_CHECKS_PASS $checks")
}
