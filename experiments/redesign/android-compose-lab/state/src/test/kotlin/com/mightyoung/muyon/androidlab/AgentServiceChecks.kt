package com.mightyoung.muyon.androidlab

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit

private val serviceBuild = "a".repeat(40)
private val serviceEpoch = "b".repeat(32)
private val serviceLease = "c".repeat(32)
private val serviceRun = "d".repeat(32)
private fun meta(revision: Long = 1, epoch: String = serviceEpoch) = UiAgentMeta(1u, serviceBuild, epoch, revision)
private fun intent(id: String = "read_1") = UiAgentIntent(id, UiAgentVariant.EQUIPMENT, serviceBuild)
private fun runIdentity() = UiAgentRunIdentity(serviceRun, serviceEpoch, UiAgentTask("task-1", "attempt-1"))
private fun completed(i: UiAgentIntent = intent()) = UiAgentRun.Terminal(UiAgentSummary(i, runIdentity(), UiAgentTerminal.COMPLETED, UiAgentReason.NONE,
    UiAgentReceipt("e".repeat(32), UiAgentReceiptOutcome.RECORDED_SUCCESS)))
private fun snap(r: UiAgentRun? = null, revision: Long = 1, phase: UiAgentServicePhase = UiAgentServicePhase.READY) = UiAgentSnapshot(meta(revision),phase,r)
private class ClientRig {
    val c = AgentServiceClientState(serviceBuild)
    val connection = c.beginBinding()
    init { check(c.connected(connection,meta(),serviceLease,UiAgentServicePhase.READY)==UiAgentApply.APPLIED) { "connect actual lease missing" } }
    fun ready() {
        val v=c.activityVisibility("activity-1",true) ?: error("visibility change missing")
        c.visibilityAcknowledged(v.client,v.generation,true)
        check(c.apply(c.capture() ?: error("current ticket missing"),snap())==UiAgentApply.APPLIED)
    }
    fun start(id:String="read_1"):UiAgentStartDecision.Submit = (c.userStart(id,UiAgentVariant.EQUIPMENT) as? UiAgentStartDecision.Submit) ?: error("explicit submit not admitted")
    fun apply(r:UiAgentRun?,revision:Long=2,kind:UiAgentObservationKind=UiAgentObservationKind.CURRENT,phase:UiAgentServicePhase=UiAgentServicePhase.READY):UiAgentApply =
        c.apply((if (kind==UiAgentObservationKind.HISTORICAL) c.captureLookup(r?.intent ?: error("lookup key missing")) else c.capture(kind)) ?: error("observation ticket missing"),snap(r,revision,phase))
}
private class ServiceManualExecutor:Executor {
    val jobs=ArrayDeque<Runnable>()
    override fun execute(command:Runnable) { jobs.addLast(command) }
    fun next() { check(jobs.isNotEmpty()) { "no scheduled work" }; jobs.removeFirst().run() }
}
private class Lifetime:AgentControllerLifetime { var retired=0; var settled=0; override fun retire(){retired++}; override fun awaitSettled(){settled++} }

private class RetainedLifetime:AgentRetainedLifetime {
    var retires=0;var waits=0;var cleanupCalls=0
    var actualClosed=false;var cleaned=false
    var onRetire:()->Unit={};var onAwait:()->Unit={}
    override val cleanupComplete get()=actualClosed && cleaned
    override fun retire(){retires++;onRetire()}
    override fun awaitSettled(){waits++;onAwait()}
}

fun runAgentServiceChecks() {
    val cases=linkedMapOf<String,()->Unit>()
    cases["precontroller initializing has no native identity or admission"]={
        val c=AgentServiceClientState(serviceBuild); val t=c.beginBinding();c.transportInitializing(t)
        check(c.transport==UiAgentTransport.INITIALIZING);check(c.client==null && c.snapshot==null)
        check(c.userStart("read_1",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Unavailable)
    }
    cases["new connection ignores late constructor transport update"]={
        val c=AgentServiceClientState(serviceBuild);val old=c.beginBinding();val fresh=c.beginBinding()
        c.transportInitializing(old);check(c.transport==UiAgentTransport.BINDING)
        check(c.connected(old,meta(),serviceLease,UiAgentServicePhase.READY)==UiAgentApply.STALE)
        check(c.connected(fresh,meta(),serviceLease,UiAgentServicePhase.READY)==UiAgentApply.APPLIED)
    }
    cases["connection rejects invalid native meta and lease"]={
        for ((m,l) in listOf(meta().copy(protocol=2u) to serviceLease,meta().copy(buildIdentity="f".repeat(40)) to serviceLease,
            meta().copy(serviceEpoch="bad") to serviceLease,meta(-1) to serviceLease,meta() to "bad")) {
            val c=AgentServiceClientState(serviceBuild);check(c.connected(c.beginBinding(),m,l,UiAgentServicePhase.READY)==UiAgentApply.INVALID)
            check(c.client==null)
        }
    }
    cases["fresh lease is invisible and reconciles before explicit user submit"]={
        val r=ClientRig();check(!r.c.visible)
        check(r.c.userStart("read_1",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Unavailable)
        val v=r.c.activityVisibility("a",true)!!;r.c.visibilityAcknowledged(v.client,v.generation,true)
        check(r.c.userStart("read_1",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.ReconcileFirst)
        r.apply(null);check(r.start().intent==intent())
    }
    cases["busy explicit double click never creates a second submit"]={val r=ClientRig();r.ready();val first=r.start();check(r.c.userStart("read_2",UiAgentVariant.RESEARCH)==UiAgentStartDecision.Busy);check(r.c.selectedIntent==first.intent)}
    cases["invalid user request identities cannot become native work"]={ val r=ClientRig();r.ready();for(id in listOf("", ".", "x".repeat(65),"read value", "读"))check(r.c.userStart(id,UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Invalid) }
    cases["native initializing recovery and closed remain unavailable"]={for(p in listOf(UiAgentServicePhase.INITIALIZING,UiAgentServicePhase.RECOVERY_REQUIRED,UiAgentServicePhase.CLOSING,UiAgentServicePhase.CLOSED)){val r=ClientRig();r.ready();r.apply(null,2,phase=p);check(r.c.userStart("read_1",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Unavailable)}}
    cases["old display lease cannot apply a later terminal"]={val r=ClientRig();r.ready();r.start();val t=r.c.capture(UiAgentObservationKind.STATUS)!!;r.c.detachDisplay();check(r.c.apply(t,snap(completed(),3))==UiAgentApply.STALE);check(r.c.snapshot?.run==null)}
    cases["old connection cannot erase original known terminal"]={val r=ClientRig();r.ready();r.apply(completed(),3);val t=r.c.capture()!!;r.c.transportLost(r.connection);check(r.c.observationUnknown);check(r.c.snapshot?.run==completed());r.c.beginBinding();check(r.c.apply(t,snap(UiAgentRun.Queued(intent()),4))==UiAgentApply.STALE);check(r.c.snapshot?.run==completed())}
    cases["lower revision cannot regress same run"]={val r=ClientRig();r.ready();r.apply(completed(),5);check(r.apply(UiAgentRun.Running(intent(),runIdentity()),4)==UiAgentApply.STALE);check(r.c.snapshot?.run==completed())}
    cases["higher revision cannot turn a settled run back into running"]={val r=ClientRig();r.ready();r.apply(completed(),5);check(r.apply(UiAgentRun.Running(intent(),runIdentity()),6)==UiAgentApply.CONFLICT);check(r.c.snapshot?.run==completed())}
    cases["equal revision requires identical authoritative snapshot"]={val r=ClientRig();r.ready();r.apply(UiAgentRun.Running(intent(),runIdentity()),5);check(r.apply(UiAgentRun.Running(intent(),runIdentity()),5)==UiAgentApply.APPLIED);check(r.apply(completed(),5)==UiAgentApply.CONFLICT)}
    cases["same live connect is idempotent without dropping observations"]={val r=ClientRig();r.ready();val t=r.c.capture()!!;check(r.c.connected(r.connection,meta(),serviceLease,UiAgentServicePhase.READY)==UiAgentApply.APPLIED);check(r.c.apply(t,snap(completed(),2))==UiAgentApply.APPLIED)}
    cases["old epoch rejects active replies after reconnect"]={val r=ClientRig();r.ready();val old=r.c.capture()!!;val n=r.c.beginBinding();check(r.c.connected(n,meta(1,"f".repeat(32)),serviceLease,UiAgentServicePhase.READY)==UiAgentApply.APPLIED);check(r.c.apply(old,snap(completed(),9))==UiAgentApply.STALE);check(r.c.userStart("read_2",UiAgentVariant.RESEARCH)==UiAgentStartDecision.Unavailable)}
    cases["current recovers lost request without producing submit"]={val r=ClientRig();r.ready();check(r.c.selectedIntent==null);r.apply(UiAgentRun.Running(intent("original"),runIdentity()),2);check(r.c.selectedIntent==intent("original"));check(r.c.userStart("new",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Busy)}
    cases["status wrong request variant source or durable binding conflicts"]={val changes=listOf<UiAgentRun>(UiAgentRun.Running(intent("other"),runIdentity()),UiAgentRun.Running(intent().copy(variant=UiAgentVariant.RESEARCH),runIdentity()),UiAgentRun.Running(intent().copy(sourceBuildIdentity="f".repeat(40)),runIdentity()),UiAgentRun.Running(intent(),runIdentity().copy(runId="f".repeat(32))))
        changes.forEach { wrong->val r=ClientRig();r.ready();r.start();r.apply(UiAgentRun.Running(intent(),runIdentity()),2);check(r.apply(wrong,3,UiAgentObservationKind.STATUS)==UiAgentApply.CONFLICT) }}
    cases["historical lookup is separate from a newer active run"]={val r=ClientRig();r.ready();r.start("new");r.apply(UiAgentRun.Running(intent("new"),runIdentity()),3);check(r.apply(completed(intent("old")),4,UiAgentObservationKind.HISTORICAL)==UiAgentApply.APPLIED);check(r.c.snapshot?.run?.intent==intent("new"));check(r.c.historical?.run?.intent==intent("old"))}
    cases["historical source build and admitted epoch stay original"]={val r=ClientRig();r.ready();val old=completed().let{it.copy(summary=it.summary.copy(intent=it.intent.copy(sourceBuildIdentity="f".repeat(40)),identity=runIdentity().copy(admittedEpoch="1".repeat(32))))};check(r.apply(old,3,UiAgentObservationKind.HISTORICAL)==UiAgentApply.APPLIED);check(r.c.historical?.run==old)}
    cases["unknown transport is not native failed cancelled or no admission"]={val r=ClientRig();r.ready();r.start();r.apply(UiAgentRun.Unresolved(intent(),null,UiAgentReceipt(null,UiAgentReceiptOutcome.UNKNOWN)),2);r.c.transportLost(r.connection);check(r.c.snapshot?.run is UiAgentRun.Unresolved);check(r.c.observationUnknown);check(r.c.userStart("retry",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Unavailable)}
    cases["recorded read success remains success when run is cancelled"]={val r=ClientRig();r.ready();val result=completed().let{it.copy(summary=it.summary.copy(terminal=UiAgentTerminal.CANCELLED,reason=UiAgentReason.CANCELLED))};check(r.apply(result,2)==UiAgentApply.APPLIED);check((r.c.snapshot?.run as UiAgentRun.Terminal).summary.receipt.outcome==UiAgentReceiptOutcome.RECORDED_SUCCESS)}
    cases["settled no admission is distinct and cannot regress"]={val r=ClientRig();r.ready();val no=UiAgentRun.SettledNoAdmission(intent(),UiAgentNoAdmissionReason.QUOTA_EXCEEDED);check(r.apply(no,3)==UiAgentApply.APPLIED);check(r.apply(UiAgentRun.Queued(intent()),4)==UiAgentApply.CONFLICT);check(r.c.snapshot?.run==no)}
    cases["completed requires actual task receipt identity and reason none"]={val good=completed();check(validAgentSnapshot(snap(good),serviceBuild));for(bad in listOf(good.summary.copy(identity=runIdentity().copy(actualTask=null)),good.summary.copy(receipt=UiAgentReceipt(null,UiAgentReceiptOutcome.RECORDED_SUCCESS)),good.summary.copy(reason=UiAgentReason.CANCELLED),good.summary.copy(receipt=UiAgentReceipt(null,UiAgentReceiptOutcome.NOT_STARTED))))check(!validAgentSnapshot(snap(UiAgentRun.Terminal(bad)),serviceBuild))}
    cases["malformed IDs and negative revision rejected without defaults"]={check(!validAgentSnapshot(snap(revision=-1),serviceBuild));check(!validAgentSnapshot(snap(UiAgentRun.Running(intent(),runIdentity().copy(runId=""))),serviceBuild));check(!validAgentSnapshot(snap(UiAgentRun.Queued(intent().copy(requestId="bad.request"))),serviceBuild));check(!validAgentSnapshot(snap(UiAgentRun.Running(intent(),runIdentity().copy(actualTask=UiAgentTask("","x")))),serviceBuild))}
    cases["all sealed snapshot variants have a valid sibling"]={val i=intent();val id=runIdentity();for(run in listOf(UiAgentRun.Queued(i),UiAgentRun.Admitted(i,id),UiAgentRun.Running(i,id),completed(),UiAgentRun.SettledNoAdmission(i,UiAgentNoAdmissionReason.CANCELLED_BEFORE_ADMISSION),UiAgentRun.Unresolved(i,null,UiAgentReceipt(null,UiAgentReceiptOutcome.UNKNOWN))))check(validAgentSnapshot(snap(run),serviceBuild))}
    cases["multiple visible activity identities do not release the last lease early"]={val r=ClientRig();val one=r.c.activityVisibility("one",true)!!;r.c.visibilityAcknowledged(one.client,one.generation,true);check(r.c.activityVisibility("one",true)==null);check(r.c.activityVisibility("two",true)==null);check(r.c.activityVisibility("one",false)==null);check(r.c.visible);val last=r.c.activityVisibility("two",false)!!;check(!last.visible && last.generation>one.generation && !r.c.visible)}
    cases["old visibility ACK cannot enable a newer invisible state"]={val r=ClientRig();val yes=r.c.activityVisibility("one",true)!!;val no=r.c.activityVisibility("one",false)!!;r.c.visibilityAcknowledged(yes.client,yes.generation,true);r.apply(null);check(r.c.userStart("new",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Unavailable);r.c.visibilityAcknowledged(no.client,no.generation,true);check(!r.c.visible)}
    cases["rotation retains run identity but cannot clear issued stop"]={val r=ClientRig();r.ready();r.start();r.apply(UiAgentRun.Running(intent(),runIdentity()),2);r.c.activityVisibility("activity-1",false);val back=r.c.activityVisibility("rotation-new",true)!!;r.c.visibilityAcknowledged(back.client,back.generation,true);check(r.c.selectedIntent==intent());check(r.c.userStart("new",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Unavailable)}
    cases["release invalidates old observation and does not claim native closed"]={val r=ClientRig();r.ready();r.start();val t=r.c.capture()!!;val release=r.c.release()!!;check(release.generation>0);check(r.c.client==null);check(r.c.apply(t,snap(completed(),9))==UiAgentApply.STALE);check(r.c.snapshot?.phase!=UiAgentServicePhase.CLOSED)}
    cases["panel detach is not visibility release"]={val r=ClientRig();r.ready();r.c.detachDisplay();check(r.c.visible && r.c.client!=null);check(r.c.release()!=null)}
    cases["post terminal new request requires explicit user action"]={val r=ClientRig();r.ready();r.apply(completed(),3);check(r.c.selectedIntent==intent());check(r.c.capture()!=null);check(r.start("second").intent.requestId=="second");check(r.c.userStart("third",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Busy)}
    cases["bootstrap late constructor is explicitly retired and drained"]={val work=ServiceManualExecutor();val obj=Lifetime();var ready=0;val b=AgentServiceBootstrap(work,{obj},{ready++},{error("not setup failure")});b.start();b.retire();work.next();check(ready==0 && obj.retired==1 && obj.settled==1)}
    cases["bootstrap initialized object settles before install and does not repeat"]={val work=ServiceManualExecutor();val obj=Lifetime();var ready=0;val b=AgentServiceBootstrap(work,{obj},{check(obj.settled==1);ready++},{error("not setup failure")});b.start();b.start();check(work.jobs.size==1);work.next();check(ready==1 && obj.retired==0 && obj.settled==1)}
    cases["bootstrap retirement during actual constructor discards late object"]={val work=ServiceManualExecutor();val obj=Lifetime();var ready=0;lateinit var b:AgentServiceBootstrap;b=AgentServiceBootstrap(work,{b.retire();obj},{ready++},{error("not setup failure")});b.start();work.next();check(ready==0 && obj.retired==1 && obj.settled==1)}
    cases["bootstrap failure never installs invented Ready"]={val work=ServiceManualExecutor();var fail=0;var ready=0;val b=AgentServiceBootstrap(work,{error("private filesystem failure")},{ready++},{fail++});b.start();work.next();check(fail==1 && ready==0)}
    cases["blocked observation cannot queue another observation but control runs"]={val entered=CountDownLatch(1);val unblock=CountDownLatch(1);val ended=CountDownLatch(1);val controlDone=CountDownLatch(1);val async=Executor{work->Thread{try{work.run()}finally{ended.countDown()}}.apply{isDaemon=true}.start()};val lane=AgentRpcLanes(async,Executor{it.run()});check(lane.observe{entered.countDown();check(unblock.await(5,TimeUnit.SECONDS))});try{check(entered.await(5,TimeUnit.SECONDS));check(!lane.observe{error("must not queue")});check(lane.control{controlDone.countDown()});check(controlDone.await(1,TimeUnit.SECONDS))}finally{unblock.countDown()};check(ended.await(5,TimeUnit.SECONDS));check(lane.observe{})}
    cases["control lane is bounded independently and releases after error"]={val obs=ServiceManualExecutor();val ctrl=ServiceManualExecutor();val lane=AgentRpcLanes(obs,ctrl);check(lane.control{throw IllegalStateException("safe test")});check(!lane.control{});runCatching{ctrl.next()};check(lane.control{});ctrl.next();check(lane.observe{});obs.next()}
    cases["RPC rejection cannot strand its local lane"]={var attempts=0;val lane=AgentRpcLanes(Executor{if(attempts++==0)throw RejectedExecutionException() else it.run()},Executor{it.run()});check(!lane.observe{});check(lane.observe{});check(lane.control{})}
    cases["new lease forwards existing activity visibility without implicit start"]={val r=ClientRig();r.ready();val n=r.c.beginBinding();check(r.c.connected(n,meta(1,"f".repeat(32)),serviceLease,UiAgentServicePhase.READY)==UiAgentApply.APPLIED);val forward=r.c.visibilityForCurrentLease()!!;check(forward.visible);check(r.c.userStart("next",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.Unavailable);r.c.visibilityAcknowledged(forward.client,forward.generation,true);check(r.c.userStart("next",UiAgentVariant.EQUIPMENT)==UiAgentStartDecision.ReconcileFirst)}
    cases["known terminal cannot be erased by a later empty current"]={val r=ClientRig();r.ready();r.apply(completed(),3);check(r.apply(null,4)==UiAgentApply.CONFLICT);check(r.c.snapshot?.run==completed())}
    cases["closed service phase cannot reopen on a later revision"]={val r=ClientRig();r.ready();r.apply(null,3,phase=UiAgentServicePhase.CLOSED);check(r.apply(null,4,phase=UiAgentServicePhase.READY)==UiAgentApply.CONFLICT);check(r.c.snapshot?.phase==UiAgentServicePhase.CLOSED)}
    cases["retirement after initialize waiter returns still performs close settlement"]={val work=ServiceManualExecutor();var settled=0;var retired=0;var ready=0;lateinit var b:AgentServiceBootstrap;val obj=object:AgentControllerLifetime{override fun retire(){retired++};override fun awaitSettled(){settled++;if(settled==1)b.retire()}};b=AgentServiceBootstrap(work,{obj},{ready++},{error("not setup failure")});b.start();work.next();check(ready==0 && retired==1 && settled==2)}
    cases["historical lookup rejects a different original request binding"]={val r=ClientRig();r.ready();val t=r.c.captureLookup(intent("original"))!!;check(r.c.apply(t,snap(completed(intent("wrong")),3))==UiAgentApply.CONFLICT);check(r.c.historical==null)}
    cases["different historical observation keys may share service revision"]={val r=ClientRig();r.ready();check(r.apply(completed(intent("one")),3,UiAgentObservationKind.HISTORICAL)==UiAgentApply.APPLIED);check(r.apply(completed(intent("two")),3,UiAgentObservationKind.HISTORICAL)==UiAgentApply.APPLIED);check(r.c.historical?.run?.intent==intent("two"))}
    cases["old status ticket cannot replace a newer explicitly selected run"]={val r=ClientRig();r.ready();r.apply(completed(),3);val old=r.c.capture(UiAgentObservationKind.STATUS)!!;r.start("second");r.apply(UiAgentRun.Running(intent("second"),runIdentity().copy(runId="f".repeat(32))),4);check(r.c.apply(old,snap(completed(),5))==UiAgentApply.STALE);check(r.c.selectedIntent==intent("second"));val current=r.c.capture(UiAgentObservationKind.STATUS)!!;check(r.c.apply(current,snap(UiAgentRun.Running(intent("second"),runIdentity().copy(runId="f".repeat(32))),5))==UiAgentApply.APPLIED)}
    cases["retirement signal handoff cannot settle before actual stop signal"]={
        val backend=ServiceManualExecutor();val firstEntered=CountDownLatch(1);val firstReturn=CountDownLatch(1);val signalEntered=CountDownLatch(1);val signalReturn=CountDownLatch(1);val initDone=CountDownLatch(1);val retireDone=CountDownLatch(1)
        val waits=java.util.concurrent.atomic.AtomicInteger();val stopped=java.util.concurrent.atomic.AtomicBoolean();val premature=java.util.concurrent.atomic.AtomicBoolean()
        val obj=object:AgentControllerLifetime{override fun retire(){signalEntered.countDown();check(signalReturn.await(5,TimeUnit.SECONDS));stopped.set(true)};override fun awaitSettled(){if(waits.incrementAndGet()==1){firstEntered.countDown();check(firstReturn.await(5,TimeUnit.SECONDS))}else if(!stopped.get())premature.set(true)}}
        var ready=0;val b=AgentServiceBootstrap(backend,{obj},{ready++},{error("not setup failure")});b.start()
        Thread{try{backend.next()}finally{initDone.countDown()}}.apply{isDaemon=true}.start();check(firstEntered.await(5,TimeUnit.SECONDS))
        Thread{try{b.retire()}finally{retireDone.countDown()}}.apply{isDaemon=true}.start()
        try{check(signalEntered.await(5,TimeUnit.SECONDS));firstReturn.countDown();check(initDone.await(5,TimeUnit.SECONDS))}finally{firstReturn.countDown();signalReturn.countDown()}
        check(retireDone.await(5,TimeUnit.SECONDS));check(!premature.get() && waits.get()==1 && ready==0);check(backend.jobs.size==1);backend.next();check(waits.get()==2 && stopped.get())
    }
    for (lateRevision in listOf(3L,2L)) {
        cases["new historical selection rejects reverse delivery at revision $lateRevision"]={
            val r=ClientRig();r.ready();r.start("active")
            r.apply(UiAgentRun.Running(intent("active"),runIdentity()),2)
            val old=r.c.captureLookup(intent("historical_a"))!!
            val newest=r.c.captureLookup(intent("historical_b"))!!
            val expected=snap(completed(intent("historical_b")),3)
            check(r.c.apply(newest,expected)==UiAgentApply.APPLIED)
            check(r.c.apply(old,snap(completed(intent("historical_a")),lateRevision))==UiAgentApply.STALE)
            check(r.c.historical==expected)
            check(r.c.selectedIntent==intent("active") && r.c.snapshot?.run is UiAgentRun.Running)
            check(r.c.apply(newest,expected)==UiAgentApply.APPLIED)
            val intentional=r.c.captureLookup(intent("historical_a"))!!
            check(r.c.apply(intentional,snap(completed(intent("historical_a")),3))==UiAgentApply.APPLIED)
        }
    }
    cases["settlement pump coalesces requests without a waiting queue"]={val work=ServiceManualExecutor();var settled=0;val pump=AgentSettlementPump(work,{settled++},{error("unexpected failure")});check(pump.request());check(pump.request());check(work.jobs.size==1);work.next();check(settled==1 && work.jobs.isEmpty());check(pump.request());work.next();check(settled==2)}
    cases["settlement requested during return stays with actual waiter"]={val work=ServiceManualExecutor();var settled=0;lateinit var pump:AgentSettlementPump;pump=AgentSettlementPump(work,{settled++;if(settled==1)check(pump.request())},{error("unexpected failure")});check(pump.request());work.next();check(settled==2 && work.jobs.isEmpty())}
    cases["settlement rejection and failure do not strand next explicit request"]={var attempts=0;var settled=0;var failed=0;val work=ServiceManualExecutor();val backend=Executor{if(attempts++==0)throw RejectedExecutionException()else work.execute(it)};val pump=AgentSettlementPump(backend,{settled++;if(settled==1)throw IllegalStateException("safe settlement failure")},{failed++});check(!pump.request());check(pump.request());work.next();check(settled==1 && failed==1);check(pump.request());work.next();check(settled==2 && failed==1)}
    cases["blocked settlement admits no concurrent waiter and preserves new request"]={val entered=CountDownLatch(1);val release=CountDownLatch(1);val done=CountDownLatch(1);val calls=java.util.concurrent.atomic.AtomicInteger();val active=java.util.concurrent.atomic.AtomicInteger();val overlap=java.util.concurrent.atomic.AtomicBoolean();val backend=Executor{job->Thread{try{job.run()}finally{done.countDown()}}.apply{isDaemon=true}.start()};val pump=AgentSettlementPump(backend,{if(active.incrementAndGet()!=1)overlap.set(true);try{if(calls.incrementAndGet()==1){entered.countDown();check(release.await(5,TimeUnit.SECONDS))}}finally{active.decrementAndGet()}},{error("unexpected failure")});check(pump.request());try{check(entered.await(5,TimeUnit.SECONDS));repeat(10){check(pump.request())}}finally{release.countDown()};check(done.await(5,TimeUnit.SECONDS));check(calls.get()==2 && !overlap.get())}
    cases["concurrent settlement request is not acknowledged before rejected dispatch"]={
        val entered=CountDownLatch(1);val reject=CountDownLatch(1);val done=CountDownLatch(1);val work=ServiceManualExecutor();val attempts=java.util.concurrent.atomic.AtomicInteger();var settled=0
        val backend=Executor{job->if(attempts.getAndIncrement()==0){entered.countDown();check(reject.await(5,TimeUnit.SECONDS));throw RejectedExecutionException()}else work.execute(job)}
        val pump=AgentSettlementPump(backend,{settled++},{error("unexpected failure")});val first=java.util.concurrent.atomic.AtomicReference<Boolean>()
        Thread{try{first.set(pump.request())}finally{done.countDown()}}.apply{isDaemon=true}.start()
        val accepted:Boolean
        try{check(entered.await(5,TimeUnit.SECONDS));accepted=pump.request()}finally{reject.countDown()}
        check(done.await(5,TimeUnit.SECONDS));check(first.get()==false)
        check(!accepted || settled>0){"PUMP_REJECT_RED: acknowledged request must not be stranded"}
        check(pump.request());work.next();check(settled==1)
    }
    cases["throwing failure listener cannot strand accepted settlement request"]={
        val entered=CountDownLatch(1);val finish=CountDownLatch(1);val done=CountDownLatch(1);val work=ServiceManualExecutor();val settled=java.util.concurrent.atomic.AtomicInteger()
        val pump=AgentSettlementPump(work,{if(settled.incrementAndGet()==1)throw IllegalStateException("safe settle failure")},{entered.countDown();check(finish.await(5,TimeUnit.SECONDS));throw IllegalStateException("safe listener failure")})
        check(pump.request());Thread{try{runCatching{work.next()}}finally{done.countDown()}}.apply{isDaemon=true}.start()
        val accepted:Boolean
        try{check(entered.await(5,TimeUnit.SECONDS));accepted=pump.request()}finally{finish.countDown()}
        check(done.await(5,TimeUnit.SECONDS));check(!accepted || settled.get()==2){"PUMP_LISTENER_RED: accepted request must survive listener failure"}
        check(pump.request());work.next();check(settled.get()==3)
    }
    cases["retirement holder reserves one construction before any object exists"]={
        val holder=AgentControllerRetention();val first=holder.reserve() ?: error("initial reservation missing")
        check(holder.retained()==null)
        check(holder.reserve()==null){"RETENTION_RESERVATION_RED: second construction must be denied"}
        check(holder.failedBeforePublish(first));check(holder.reserve()!=null)
    }
    cases["retirement holder publishes strong object before first await"]={
        val holder=AgentControllerRetention();val lease=holder.reserve()!!;val obj=RetainedLifetime()
        check(holder.publish(lease,obj));obj.onAwait={println("RETENTION_PUBLICATION_REACHED");check(holder.retained()===obj){"RETENTION_PUBLICATION_RED: first await must have process owner"}}
        obj.awaitSettled();check(obj.waits==1 && obj.cleanupCalls==0)
    }
    cases["throwing retirement retains original object and denies replacement"]={
        val holder=AgentControllerRetention();val lease=holder.reserve()!!;val obj=RetainedLifetime();check(holder.publish(lease,obj))
        obj.onRetire={throw IllegalStateException("injected retire failure")};check(runCatching{obj.retire()}.isFailure)
        println("RETENTION_RETIRE_FAILURE_REACHED");check(obj.retires==1 && obj.waits==0 && !obj.cleanupComplete)
        check(holder.retained()===obj){"RETENTION_RETIRE_RED: native failure cannot abandon original object"}
        check(holder.reserve()==null && !holder.releaseCleaned(lease,obj));check(obj.cleanupCalls==0)
    }
    for((label,error) in listOf("exception" to IllegalStateException("injected await failure"),"linkage" to UnsatisfiedLinkError("injected await linkage"))) {
        cases["throwing await $label retains original object without retry"]={
            val holder=AgentControllerRetention();val lease=holder.reserve()!!;val obj=RetainedLifetime();check(holder.publish(lease,obj))
            obj.onAwait={throw error};check(runCatching{obj.awaitSettled()}.isFailure)
            println("RETENTION_AWAIT_${label.uppercase()}_REACHED");check(obj.waits==1 && obj.cleanupCalls==0 && !obj.cleanupComplete)
            check(holder.retained()===obj){"RETENTION_AWAIT_RED: failed await must retain original object"}
            check(holder.reserve()==null && !holder.releaseCleaned(lease,obj));check(obj.waits==1)
        }
    }
    cases["nonclosed settlement retains owner until later actual closed cleanup"]={
        val holder=AgentControllerRetention();val lease=holder.reserve()!!;val obj=RetainedLifetime();check(holder.publish(lease,obj))
        obj.awaitSettled();check(!obj.actualClosed && !obj.cleanupComplete)
        check(holder.retained()===obj){"RETENTION_NONCLOSED_RED: a returned waiter alone is not Closed"}
        check(!holder.releaseCleaned(lease,obj) && holder.reserve()==null)
        obj.onAwait={obj.actualClosed=true;obj.cleanupCalls++;obj.cleaned=true};obj.awaitSettled()
        check(holder.releaseCleaned(lease,obj) && holder.retained()==null);check(obj.waits==2 && obj.cleanupCalls==1)
    }
    cases["closed with throwing handle cleanup retains owner until successful cleanup"]={
        val holder=AgentControllerRetention();val lease=holder.reserve()!!;val obj=RetainedLifetime();check(holder.publish(lease,obj))
        obj.onAwait={obj.actualClosed=true;obj.cleanupCalls++;throw IllegalStateException("injected handle cleanup failure")}
        check(runCatching{obj.awaitSettled()}.isFailure);println("RETENTION_CLEANUP_FAILURE_REACHED")
        check(obj.actualClosed && !obj.cleanupComplete && obj.cleanupCalls==1)
        check(holder.retained()===obj){"RETENTION_CLEANUP_RED: Closed without successful cleanup must remain retained"}
        check(!holder.releaseCleaned(lease,obj) && holder.reserve()==null)
        obj.onAwait={obj.cleanupCalls++;obj.cleaned=true};obj.awaitSettled();check(holder.releaseCleaned(lease,obj));check(holder.retained()==null && obj.cleanupCalls==2)
    }
    cases["stale retirement token cannot clear replacement after genuine cleanup"]={
        val holder=AgentControllerRetention();val a=holder.reserve()!!;val old=RetainedLifetime();check(holder.publish(a,old))
        old.actualClosed=true;old.cleaned=true;check(holder.releaseCleaned(a,old)){"RETENTION_CLEAN_RELEASE_RED: proven cleanup must release once"}
        check(!holder.releaseCleaned(a,old));val b=holder.reserve()!!;val fresh=RetainedLifetime();check(holder.publish(b,fresh))
        check(!holder.releaseCleaned(a,old) && !holder.failedBeforePublish(a));check(holder.retained()===fresh && holder.reserve()==null)
        fresh.actualClosed=true;fresh.cleaned=true;check(!holder.releaseCleaned(a,fresh));check(holder.retained()===fresh);check(holder.releaseCleaned(b,fresh))
    }
    cases["definite preobject failure releases only its unpublished reservation"]={
        val holder=AgentControllerRetention();val a=holder.reserve()!!
        check(runCatching{error("injected before object creation")}.isFailure)
        check(holder.failedBeforePublish(a)){"RETENTION_PREOBJECT_RED: definite preobject failure must release reservation"}
        val b=holder.reserve()!!;val fresh=RetainedLifetime();check(holder.publish(b,fresh))
        check(!holder.failedBeforePublish(a) && !holder.failedBeforePublish(b));check(holder.retained()===fresh && holder.reserve()==null)
    }
    cases["destroyed service late constructor remains owned through explicit retirement"]={
        val holder=AgentControllerRetention();val lease=holder.reserve()!!;val obj=RetainedLifetime();val work=ServiceManualExecutor();var installed=0
        val bootstrap=AgentServiceBootstrap(work,{check(holder.publish(lease,obj));obj},{installed++},{error("unexpected constructor failure")})
        bootstrap.start();bootstrap.retire();work.next()
        check(installed==0 && obj.retires==1 && obj.waits==1 && !obj.cleanupComplete)
        check(holder.retained()===obj){"RETENTION_LATE_CONSTRUCTOR_RED: destroyed Service cannot abandon late controller"}
        check(holder.reserve()==null)
        obj.actualClosed=true;obj.cleaned=true;check(holder.releaseCleaned(lease,obj));check(holder.reserve()!=null)
    }
    var failures=0
    cases.forEach{(name,test)->try{test();println("PASS B service $name")}catch(e:Throwable){failures++;println("FAIL B service $name: ${e.message}")}}
    check(failures==0){"$failures/${cases.size} B service state checks failed"}
    println("${cases.size}/${cases.size} B service state checks passed; Android Binder/native runtime NOT_RUN")
}
