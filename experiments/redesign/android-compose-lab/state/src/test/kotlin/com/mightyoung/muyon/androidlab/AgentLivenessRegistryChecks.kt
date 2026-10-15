package com.mightyoung.muyon.androidlab

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private class RegistryToken {
    var links=0;var alive=true;var death:(()->Unit)?=null
    fun link(callback:()->Unit):Boolean { links++;death=callback;return alive }
    fun die(){alive=false;death?.invoke()}
}
fun runAgentLivenessRegistryChecks(){
    val build="a".repeat(40);val epoch="b".repeat(32);val m=UiAgentMeta(1u,build,epoch,1)
    fun connected(key:String)=UiAgentWireReply.Connected(m,UiAgentClientRef(epoch,key.reversed()),UiAgentServicePhase.READY)
    val cases=linkedMapOf<String,()->Unit>()
    cases["private keys never repeat after dead token replacement"]={val keys=AgentClientKeys("a".repeat(16));val seen=mutableSetOf<String>();repeat(100){val key=keys.next();check(Regex("[0-9a-f]{32}").matches(key));check(seen.add(key))}}
    cases["same live token links once and keeps its native correlation key"]={val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){};val token=RegistryToken();val keys=mutableListOf<String>();repeat(2){check(registry.connect(token,token::link){key->keys+=key;connected(key)} is UiAgentWireReply.Connected)};check(token.links==1 && keys.distinct().size==1 && registry.retainedTokens()==1)}
    cases["released live tombstone consumes capacity and cannot resurrect"]={val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){};val one=RegistryToken();val two=RegistryToken();val first=registry.connect(one,one::link,::connected) as UiAgentWireReply.Connected;check(registry.markReleased(first.client));check(registry.connect(two,two::link,::connected) is UiAgentWireReply.Connected);check(registry.connect(one,one::link){error("released key reused")}==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE));val third=RegistryToken();check(registry.connect(third,third::link){error("third native call")}==UiAgentWireReply.Local(UiAgentLocalStatus.BUSY));check(third.links==0 && registry.retainedTokens()==2)}
    cases["death during link cannot gain a native lease"]={var calls=0;val gone=mutableListOf<String>();val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){gone+=it};val token=RegistryToken();val result=registry.connect(token,{death->death();false}){calls++;connected(it)};check(result==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE));check(calls==0 && gone.isNotEmpty() && registry.retainedTokens()==0)}
    cases["death inside native connect rejects late lease and stops original key again"]={val events=mutableListOf<String>();val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){events+="gone:$it"};val token=RegistryToken();val result=registry.connect(token,token::link){key->token.die();events+="returned:$key";connected(key)};check(result==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE));check(events.last().startsWith("gone:") && events.count{it.startsWith("gone:")}==2);check(registry.retainedTokens()==0)}
    cases["late original death callback cannot remove replacement"]={val gone=mutableListOf<String>();val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){gone+=it};val old=RegistryToken();registry.connect(old,old::link,::connected);val late=old.death!!;old.die();val fresh=RegistryToken();val replacement=registry.connect(fresh,fresh::link,::connected) as UiAgentWireReply.Connected;late();check(registry.retainedTokens()==1);check(gone.size==1);check((registry.connect(fresh,fresh::link,::connected) as UiAgentWireReply.Connected).client==replacement.client)}
    cases["unknown lease cannot tombstone a registered client"]={val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){};val token=RegistryToken();val first=registry.connect(token,token::link,::connected) as UiAgentWireReply.Connected;check(!registry.markReleased(first.client.copy(lease="f".repeat(32))));check(registry.connect(token,token::link,::connected)==first)}
    cases["inflight same token connect returns busy without second native call"]={val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){};val token=RegistryToken();val result=registry.connect(token,token::link){key->check(registry.connect(token,token::link){error("second native call")}==UiAgentWireReply.Local(UiAgentLocalStatus.BUSY));connected(key)};check(result is UiAgentWireReply.Connected && token.links==1)}
    cases["native connect and gone listeners execute outside registry lock"]={lateinit var registry:AgentLivenessRegistry<RegistryToken>;fun independentRead(){val done=CountDownLatch(1);Thread{registry.retainedTokens();done.countDown()}.apply{isDaemon=true}.start();check(done.await(5,TimeUnit.SECONDS))};registry=AgentLivenessRegistry(AgentClientKeys("a".repeat(16))){independentRead()};val token=RegistryToken();check(registry.connect(token,token::link){key->independentRead();connected(key)} is UiAgentWireReply.Connected);token.die();check(registry.retainedTokens()==0)}
    cases["failed death-link setup cannot create an unobserved native lease"]={var calls=0;val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){};val token=RegistryToken();check(registry.connect(token,{throw IllegalStateException("safe link failure")}){calls++;connected(it)}==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE));check(calls==0 && registry.retainedTokens()==0)}
    cases["acknowledged release cannot be revived by inflight repeat connect"]={
        var gone=0;val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){gone++};val token=RegistryToken()
        val first=registry.connect(token,token::link,::connected) as UiAgentWireReply.Connected
        check(registry.connect(token,token::link,::connected)==first)
        val entered=CountDownLatch(1);val returned=CountDownLatch(1);val done=CountDownLatch(1)
        val result=java.util.concurrent.atomic.AtomicReference<UiAgentWireReply?>()
        Thread{try{result.set(registry.connect(token,token::link){key->entered.countDown();check(returned.await(5,TimeUnit.SECONDS));connected(key)})}finally{done.countDown()}}.apply{isDaemon=true}.start()
        try{check(entered.await(5,TimeUnit.SECONDS));check(registry.markReleased(first.client))}finally{returned.countDown()}
        check(done.await(5,TimeUnit.SECONDS));check(result.get()==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE))
        check(registry.retainedTokens()==1 && gone==0 && token.links==1)
        var unexpected=0;check(registry.connect(token,token::link){unexpected++;connected(it)}==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE));check(unexpected==0)
    }
    cases["dispose unlinks live and released tokens without claiming native stop"]={var unlinked=0;var gone=0;val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){gone++};val one=RegistryToken();val two=RegistryToken();val first=registry.connectLinked(one,one::link,{unlinked++},::connected) as UiAgentWireReply.Connected;registry.connectLinked(two,two::link,{unlinked++},::connected);check(registry.markReleased(first.client));registry.dispose();registry.dispose();check(unlinked==2 && registry.retainedTokens()==0 && gone==0);one.die();two.die();check(unlinked==2 && gone==0);check(registry.connect(RegistryToken(),{true}){error("disposed native call")}==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE))}
    cases["dispose during death-link setup detaches the eventual link"]={val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){};val token=RegistryToken();val entered=CountDownLatch(1);val finish=CountDownLatch(1);val done=CountDownLatch(1);var unlinked=0;var calls=0;val result=java.util.concurrent.atomic.AtomicReference<UiAgentWireReply?>();Thread{try{result.set(registry.connectLinked(token,{death->token.link(death);entered.countDown();check(finish.await(5,TimeUnit.SECONDS));true},{unlinked++}){calls++;connected(it)})}finally{done.countDown()}}.apply{isDaemon=true}.start();try{check(entered.await(5,TimeUnit.SECONDS));registry.dispose();check(unlinked==0)}finally{finish.countDown()};check(done.await(5,TimeUnit.SECONDS));check(result.get()==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE) && unlinked==1 && calls==0)}
    cases["dispose rejects late native connect and stops only its original key"]={val gone=mutableListOf<String>();val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){gone+=it};val token=RegistryToken();var unlinked=0;var key="";val result=registry.connectLinked(token,token::link,{unlinked++}){value->key=value;registry.dispose();connected(value)};check(result==UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE));check(unlinked==1 && gone==listOf(key));check(registry.retainedTokens()==0)}
    cases["unlink callback executes outside registry admission lock"]={lateinit var registry:AgentLivenessRegistry<RegistryToken>;registry=AgentLivenessRegistry(AgentClientKeys("a".repeat(16))){};val token=RegistryToken();var called=false;registry.connectLinked(token,token::link,{called=true;val done=CountDownLatch(1);Thread{registry.retainedTokens();done.countDown()}.apply{isDaemon=true}.start();check(done.await(5,TimeUnit.SECONDS))},::connected);registry.dispose();check(called)}
    cases["dispose attempts second unlink when first unlink fails"]={
        var first=0;var second=0;var gone=0
        val registry=AgentLivenessRegistry<RegistryToken>(AgentClientKeys("a".repeat(16))){gone++}
        val one=RegistryToken();val two=RegistryToken()
        check(registry.connectLinked(one,one::link,{first++;println("DISPOSAL_UNLINK_FAILURE_REACHED");throw IllegalStateException("safe unlink failure")},::connected) is UiAgentWireReply.Connected)
        check(registry.connectLinked(two,two::link,{second++},::connected) is UiAgentWireReply.Connected)
        runCatching{registry.dispose()}
        check(second==1){"DISPOSAL_RED: second recipient must still be attempted"}
        check(first==1 && gone==0 && registry.retainedTokens()==0)
        registry.dispose();check(first==1 && second==1 && gone==0)
    }
    var failed=0;cases.forEach{(name,test)->try{test();println("PASS B liveness $name")}catch(e:Throwable){failed++;println("FAIL B liveness $name: ${e.message}")}}
    check(failed==0){"$failed/${cases.size} B liveness checks failed"}
    println("${cases.size}/${cases.size} B liveness checks passed; real Binder death/process runtime NOT_RUN")
}
